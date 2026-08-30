//
//  CalculAnalyseCorrections.swift
//  diaviz
//

import Foundation

// MARK: - Entrées (value types, découplés de SwiftData)

/// Faits bruts nécessaires à l'analyse B3, mappés en value types par le
/// service hub pour que le calculateur reste **pur**.
nonisolated struct EntreesCorrections: Sendable {
    /// Nuits ancrées par B1 (même type que B2 — partage l'ancrage lente).
    let nuits: [AncrageNuit]
    let lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)]
    let rapides: [(heure: Date, dose: Double, correction: Bool)]
    /// Repas **hors resucrages** (les repas badgés basculent ci-dessous).
    let repas: [(heure: Date, glucides: Int)]
    /// Resucrages `(heure, glucides, intention)` — comptent dans les glucides
    /// autour de la correction au même titre qu'une collation.
    let resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)]
    let sports: [(debut: Date, resume: SportResume)]
    let pauses: [(debut: Date, fin: Date?)]
}

nonisolated struct ConfigCorrections: Sendable {
    /// Cible haute (mg/dL) — au-delà, une correction jugée « insuffisante »
    /// si la glycémie n'y redescend pas. Profil (`seuilsGlycemiques.hyperglycemie`).
    var cibleHaute: Int = 180
    /// Seuil hypo (mg/dL) — sous ce seuil dans les 6h : « sur-correction ».
    var seuilHypo: Int = 70
    var diaHeures: Double = 4
    var picMinutes: Double = 75
}

/// Assembleur **B3 — corrections du soir** : dérivation pure, jamais
/// persistée. **Event-based** : chaque correction rapide survenue dans la
/// fenêtre de coucher d'une nuit (zones 1+2 de B1, lente −3h → lente +2h) est
/// classée selon la trajectoire glycémique qui suit — sans seuil de glycémie
/// de déclenchement (≠ B2).
///
/// Classification (recall prioritaire sur la sur-correction, l'événement
/// dangereux) :
/// - **sur-correction** : hypo (< `seuilHypo`) dans les 6h suivant la correction ;
/// - **insuffisante** : reste au-dessus de `cibleHaute` pendant les 2h qui suivent ;
/// - **adaptée** : ni l'un ni l'autre.
///
/// Doc : Eraser « Diaviz / B3 — Corrections du soir ».
nonisolated enum CalculAnalyseCorrections {

    private static let fenetreSurCorrection: TimeInterval = 6 * 3600
    private static let fenetreInsuffisance: TimeInterval = 2 * 3600

    // MARK: - Point d'entrée

    static func analyser(
        entrees: EntreesCorrections,
        changementDoseRecent: Date?,
        config: ConfigCorrections = ConfigCorrections()
    ) -> AnalyseCorrections {
        let cal = Calendar.current
        let nuitsRetenues = entrees.nuits
            .filter { $0.doseLente > 0 }
            .filter { avantChangement($0.dateNuit, changement: changementDoseRecent, cal: cal) == false }

        let corrections: [CorrectionSoir] = nuitsRetenues.flatMap { nuit in
            correctionsDeLaNuit(nuit, entrees: entrees, config: config, cal: cal)
        }
        .sorted { $0.glycemie < $1.glycemie }

        return AnalyseCorrections(corrections: corrections)
    }

    private static func avantChangement(_ date: Date, changement: Date?, cal: Calendar) -> Bool {
        guard let changement else { return false }
        return cal.startOfDay(for: date) < cal.startOfDay(for: changement)
    }

    // MARK: - Corrections d'une nuit

    private static func correctionsDeLaNuit(
        _ nuit: AncrageNuit,
        entrees: EntreesCorrections,
        config: ConfigCorrections,
        cal: Calendar
    ) -> [CorrectionSoir] {
        let L = nuit.basaleTime
        let z1 = L.addingTimeInterval(-3 * 3600)...L
        let z2 = L...L.addingTimeInterval(2 * 3600)

        let enPause = entrees.pauses.contains { p in
            let fin = p.fin ?? z2.upperBound
            return fin >= z1.lowerBound && p.debut <= z2.upperBound
        }
        guard !enPause else { return [] }

        let correctionsFenetre = entrees.rapides.filter {
            $0.correction && (z1.contains($0.heure) || z2.contains($0.heure))
        }

        return correctionsFenetre.compactMap { correction in
            construireCorrection(correction, entrees: entrees, config: config, jour: nuit.dateNuit, cal: cal)
        }
    }

    private static func construireCorrection(
        _ correction: (heure: Date, dose: Double, correction: Bool),
        entrees: EntreesCorrections,
        config: ConfigCorrections,
        jour: Date, cal: Calendar
    ) -> CorrectionSoir? {
        let heure = correction.heure
        guard let issue = issueCorrection(entrees.lectures, apres: heure, config: config) else {
            return nil   // pas encore assez de recul CGM pour classer
        }

        let glycemie = valeurProche(entrees.lectures, a: heure) ?? 0
        let tendance = tendanceProche(entrees.lectures, a: heure) ?? .stable
        let glucides = glucidesAutour(entrees.repas, resucrages: entrees.resucrages, a: heure)
        let sport = sportDuJour(entrees.sports, jour: jour, cal: cal)
        let charge = CalculChargeActivite.charge(
            jusqua: jour,
            activites: entrees.sports.map { (debut: $0.debut, dureeMin: 0) }
        )
        let iob = iobAvantCorrection(entrees.rapides, a: heure, config: config)

        return CorrectionSoir(
            id: UUID(), date: heure, glycemie: glycemie, tendance: tendance,
            glucides: glucides, dose: correction.dose, iob: iob,
            sport: sport, charge: charge, issue: issue
        )
    }

    // MARK: - Classification

    /// `nil` si pas assez de CGM après la correction pour trancher (nuit trop
    /// récente) — cette correction n'est alors pas encore affichable.
    private static func issueCorrection(
        _ lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)],
        apres heure: Date,
        config: ConfigCorrections
    ) -> IssueCorrection? {
        let fenetre6h = lectures.filter {
            $0.date > heure && $0.date <= heure.addingTimeInterval(fenetreSurCorrection)
        }
        guard !fenetre6h.isEmpty else { return nil }

        // Priorité : sur-correction (l'événement dangereux), recherché sur
        // toute la fenêtre 6h.
        if fenetre6h.contains(where: { $0.valeur < config.seuilHypo }) {
            return .surCorrection
        }

        let fenetre2h = fenetre6h.filter { $0.date <= heure.addingTimeInterval(fenetreInsuffisance) }
        guard !fenetre2h.isEmpty else { return nil }

        let resteHaut = fenetre2h.allSatisfy { $0.valeur > config.cibleHaute }
        return resteHaut ? .insuffisant : .adapte
    }

    // MARK: - Contexte (partagé avec B2)

    private static func valeurProche(
        _ lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)], a instant: Date
    ) -> Int? {
        lectures.min(by: { abs($0.date.timeIntervalSince(instant)) < abs($1.date.timeIntervalSince(instant)) })?.valeur
    }

    private static func tendanceProche(
        _ lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)], a instant: Date
    ) -> TendanceGlycemie? {
        lectures.min(by: { abs($0.date.timeIntervalSince(instant)) < abs($1.date.timeIntervalSince(instant)) })?.tendance
    }

    /// Glucides autour de la correction — collations **et** resucrages.
    private static func glucidesAutour(
        _ repas: [(heure: Date, glucides: Int)],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)],
        a instant: Date
    ) -> Double? {
        let fenetre = instant.addingTimeInterval(-1800)...instant.addingTimeInterval(3600)
        let total = repas.filter { fenetre.contains($0.heure) }.reduce(0) { $0 + $1.glucides }
            + resucrages.filter { fenetre.contains($0.heure) }.reduce(0) { $0 + $1.glucides }
        return total > 0 ? Double(total) : nil
    }

    private static func sportDuJour(
        _ sports: [(debut: Date, resume: SportResume)], jour: Date, cal: Calendar
    ) -> SportResume? {
        sports.first { cal.isDate($0.debut, inSameDayAs: jour) }?.resume
    }

    private static func iobAvantCorrection(
        _ rapides: [(heure: Date, dose: Double, correction: Bool)],
        a instant: Date, config: ConfigCorrections
    ) -> Double? {
        let injections = rapides
            .filter { $0.heure < instant }
            .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) }
        let iob = IOBCalculateur.iob(a: instant, injections: injections, diaHeures: config.diaHeures, picMinutes: config.picMinutes)
        return iob > 0.05 ? iob : nil
    }
}
