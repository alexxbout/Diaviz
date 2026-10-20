//
//  CalculEligibiliteRepas.swift
//  diaviz
//

import Foundation

/// Ratio qu'un repas peut juger : celui de son moment, ou le ratio sport
/// d'un type de séance quand ce ratio était en vigueur.
nonisolated enum RatioJuge: Hashable, Sendable {
    case moment
    /// `TypeSport.rawValue`.
    case sport(type: String)
}

/// Pourquoi un repas ne peut juger aucun ratio.
nonisolated enum RaisonEcartRepas: Hashable, Sendable {
    /// Bascule « Exclure des analyses » du repas.
    case exclusManuellement
    /// Événement / contexte libre, jamais interprété.
    case contexteLibre
    /// Ajustement intentionnel : la dose dévie volontairement du ratio.
    case ajuste
    /// La courbe ne mesure pas que ce repas (`CalculExclusionsFenetre`).
    case fenetre(RaisonExclusionFenetre)

    var libelle: String {
        switch self {
        case .exclusManuellement: "exclu à la main"
        case .contexteLibre:      "contexte libre"
        case .ajuste:             "ajusté"
        case .fenetre(let r):     r.libelle
        }
    }
}

/// Un repas tel que la règle d'éligibilité le voit — value type, sans
/// SwiftData.
nonisolated struct RepasAJuger: Sendable {
    let id: UUID
    let heure: Date
    let doseCorrection: Double?
    let exclureDesAnalyses: Bool
    let aUnEvenement: Bool
    let ajuste: Bool
}

/// Séance dont le type a un ratio sport renseigné.
nonisolated struct SeanceRatioSport: Sendable, Equatable {
    let debut: Date
    let fin: Date
    let type: String
}

nonisolated struct EligibiliteRepas: Sendable, Equatable {
    let ratio: RatioJuge
    /// Vide si le repas peut juger `ratio`. Une raison de base au plus
    /// (exclu, contexte libre, ajusté), sinon toutes les raisons de fenêtre.
    let raisons: [RaisonEcartRepas]

    var estEligible: Bool { raisons.isEmpty }
}

/// **Règle unique** : ce repas peut-il juger un ratio, et lequel ? Utilisée
/// par l'analyse des ratios (R1) et par les épisodes de charge (C1) — une
/// règle changée ici s'applique partout. Doc : R1 « Repas pollués par leur
/// fenêtre », C1 § 7.
nonisolated enum CalculEligibiliteRepas {

    static func evaluer(
        _ repas: RepasAJuger,
        faits: FaitsFenetreRepas,
        seancesRatioSport: [SeanceRatioSport],
        fenetreEffetSport: TimeInterval,
        raisonsIgnorees: Set<RaisonExclusionFenetre> = []
    ) -> EligibiliteRepas {
        // Ratio sport en vigueur : séance commencée avant le repas et
        // terminée depuis moins que la fenêtre d'effet (séance en cours
        // comprise). Même règle que la saisie (`InsightsService`).
        let seance = seancesRatioSport
            .filter { $0.debut <= repas.heure && repas.heure.timeIntervalSince($0.fin) <= fenetreEffetSport }
            .max { $0.fin < $1.fin }
        let ratio: RatioJuge = seance.map { .sport(type: $0.type) } ?? .moment

        if repas.exclureDesAnalyses { return EligibiliteRepas(ratio: ratio, raisons: [.exclusManuellement]) }
        if repas.aUnEvenement { return EligibiliteRepas(ratio: ratio, raisons: [.contexteLibre]) }
        if repas.ajuste { return EligibiliteRepas(ratio: ratio, raisons: [.ajuste]) }

        // La séance qui déclenche le ratio sport n'est pas une pollution :
        // sans ça, aucun repas après le sport ne pourrait juger ce ratio.
        // Une autre séance dans la fenêtre en reste une.
        var faitsJuges = faits
        if let seance {
            faitsJuges.seances.removeAll { $0.debut == seance.debut && $0.fin == seance.fin }
        }
        let fenetre = CalculExclusionsFenetre.raisons(
            repasId: repas.id, heure: repas.heure, doseCorrection: repas.doseCorrection, faits: faitsJuges
        ).subtracting(raisonsIgnorees)
        return EligibiliteRepas(
            ratio: ratio,
            raisons: RaisonExclusionFenetre.allCases.filter(fenetre.contains).map { .fenetre($0) }
        )
    }
}
