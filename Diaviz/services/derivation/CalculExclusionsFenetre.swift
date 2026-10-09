//
//  CalculExclusionsFenetre.swift
//  diaviz
//

import Foundation

/// Pourquoi la courbe d'un repas ne mesure pas **que** lui — chaque raison
/// suffit seule à écarter le repas de l'analyse des ratios (R1) et de la
/// carte « Repas à revoir ». Voir doc R1 « Repas pollués par leur fenêtre ».
nonisolated enum RaisonExclusionFenetre: String, CaseIterable, Hashable, Sendable {
    /// Un autre repas tombe dans la fenêtre [T−1h, T+4h].
    case autreRepas
    /// Insuline rapide d'une injection précédente encore active au début du
    /// repas, au-dessus de `CalculExclusionsFenetre.seuilInsulineActive`.
    case insulineActive
    /// Correction d'insuline dans la fenêtre — y compris celle faite **avec**
    /// le repas : elle part d'une glycémie haute, deux inconnues sur une courbe.
    case correction
    /// Resucrage pris dans la fenêtre.
    case resucrage
    /// Séance de sport qui chevauche la fenêtre.
    case sport

    var libelle: String {
        switch self {
        case .autreRepas:     "autre repas dans les 4 h"
        case .insulineActive: "insuline encore active"
        case .correction:     "correction"
        case .resucrage:      "resucrage"
        case .sport:          "sport"
        }
    }
}

/// Faits du hub autour des repas, en value types — le calcul reste pur et
/// testable sans `ModelContext`.
nonisolated struct FaitsFenetreRepas: Sendable {
    struct RepasFait: Sendable { let id: UUID; let heure: Date }
    struct InjectionFait: Sendable {
        let heure: Date
        let dose: Double
        /// Rapide (repas ou correction) — la lente n'entre pas dans l'IOB.
        let estRapide: Bool
        let estCorrection: Bool
        let repasAssocieId: UUID?
    }
    struct SeanceFait: Sendable { let debut: Date; let fin: Date }

    var repas: [RepasFait] = []
    var injections: [InjectionFait] = []
    var resucrages: [Date] = []
    var seances: [SeanceFait] = []
    var diaHeures: Double = 4
    var picMinutes: Double = 75
}

/// Exclusion **la plus restrictive possible** : un repas ne compte pour juger
/// un ratio que si sa courbe ne mesure que lui. Toutes les raisons sont
/// retournées, pas seulement la première.
nonisolated enum CalculExclusionsFenetre {

    /// IOB minimal (u) au début du repas pour l'écarter. 0,5 u = plus petit
    /// pas d'un stylo demi-unité, ≈ 5 g de glucides à 1u/10g : sous l'erreur
    /// courante d'estimation des glucides. Plus bas, on écarterait sur la
    /// queue du modèle IOB, qui dépend surtout de la DIA saisie. Registre :
    /// docs/architecture « Paramètres à calibrer ».
    static let seuilInsulineActive = 0.5

    static func raisons(
        repasId: UUID, heure: Date, doseCorrection: Double?, faits: FaitsFenetreRepas
    ) -> Set<RaisonExclusionFenetre> {
        let debut = heure.addingTimeInterval(AssembleurReponseRepas.debutFenetre)
        let fin = heure.addingTimeInterval(AssembleurReponseRepas.finFenetre)
        let dansFenetre = { (d: Date) in d >= debut && d <= fin }
        var raisons: Set<RaisonExclusionFenetre> = []

        if faits.repas.contains(where: { $0.id != repasId && dansFenetre($0.heure) }) {
            raisons.insert(.autreRepas)
        }

        if (doseCorrection ?? 0) > 0
            || faits.injections.contains(where: { $0.estCorrection && dansFenetre($0.heure) }) {
            raisons.insert(.correction)
        }

        // IOB des injections **antérieures** au repas, hors bolus de ce repas
        // (pré-bolus quelques minutes avant : il fait partie de la mesure).
        let precedentes = faits.injections
            .filter { $0.estRapide && $0.heure < heure && $0.repasAssocieId != repasId }
            .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) }
        let iob = IOBCalculateur.iob(
            a: heure, injections: precedentes, diaHeures: faits.diaHeures, picMinutes: faits.picMinutes
        )
        if iob >= seuilInsulineActive { raisons.insert(.insulineActive) }

        if faits.resucrages.contains(where: dansFenetre) { raisons.insert(.resucrage) }

        if faits.seances.contains(where: { $0.debut <= fin && $0.fin >= debut }) {
            raisons.insert(.sport)
        }
        return raisons
    }
}
