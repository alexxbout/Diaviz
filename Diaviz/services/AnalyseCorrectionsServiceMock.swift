//
//  AnalyseCorrectionsServiceMock.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import Foundation

// MARK: - Issue d'une correction du soir

/// Résultat **factuel** d'une correction prise au coucher, classé selon où la
/// glycémie a atterri par rapport à la cible. Observation rétrospective, jamais
/// une recommandation de dose.
enum IssueCorrection: Sendable, Equatable {

    /// La glycémie est restée au-dessus de la cible (correction trop faible).
    case insuffisant

    /// La glycémie est revenue en cible.
    case adapte

    /// La glycémie est descendue sous la cible / hypo (correction trop forte).
    case surCorrection
}

// MARK: - Une correction du soir

/// Une correction d'insuline rapide prise au coucher, avec son contexte et son
/// issue. B3 est **event-based** : déclenché par la présence d'une correction,
/// sans seuil de glycémie.
struct CorrectionSoir: Identifiable, Sendable, Equatable {

    let id: UUID
    let date: Date

    /// Glycémie (mg/dL) au moment de la correction.
    let glycemie: Int

    /// Tendance de la glycémie au moment de la correction (trajectoire).
    let tendance: TendanceGlycemie

    /// Glucides ingérés autour de la correction (g). `nil` si aucun.
    let glucides: Double?

    /// Dose de correction (unités de rapide).
    let dose: Double

    /// IOB résiduel au moment de la correction (unités). `nil` si nul.
    /// Facteur clé : corriger par-dessus de l'IOB → risque de sur-correction.
    let iob: Double?

    /// Séance de sport le jour même (détail au tap). `nil` si aucune.
    let sport: SportResume?

    /// Charge d'activité de la semaine (contexte transverse).
    let charge: ChargeActivite

    let issue: IssueCorrection
}

// MARK: - Snapshot B3

/// Snapshot prêt à afficher de l'analyse « Corrections du soir ».
/// `corrections` triée par glycémie croissante (l'axe de comparaison premier).
struct AnalyseCorrections: Sendable, Equatable {

    let corrections: [CorrectionSoir]

    var nombre: Int { corrections.count }
}

// MARK: - Mock

extension AnalyseCorrections {

    /// Jeu typique : corrections variées, les sur-corrections corrélées à un
    /// IOB résiduel ou une semaine chargée (sensibilité accrue).
    static var mock: AnalyseCorrections {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        func jour(_ i: Int) -> Date { base.addingTimeInterval(Double(i) * 86_400) }

        let corrections: [CorrectionSoir] = [
            .init(id: UUID(), date: jour(0), glycemie: 178, tendance: .hausse,      glucides: nil, dose: 2, iob: nil, sport: nil,                                                          charge: .calme,   issue: .adapte),
            .init(id: UUID(), date: jour(1), glycemie: 190, tendance: .stable,      glucides: nil, dose: 3, iob: nil, sport: nil,                                                          charge: .calme,   issue: .adapte),
            .init(id: UUID(), date: jour(2), glycemie: 198, tendance: .hausse,      glucides: nil, dose: 3, iob: 1.5, sport: nil,                                                          charge: .moderee, issue: .surCorrection),
            .init(id: UUID(), date: jour(3), glycemie: 205, tendance: .stable,      glucides: nil, dose: 3, iob: nil, sport: SportResume(type: "Course", intensite: "intense", dureeMinutes: 50), charge: .intense, issue: .surCorrection),
            .init(id: UUID(), date: jour(4), glycemie: 212, tendance: .hausse,      glucides: nil, dose: 4, iob: nil, sport: nil,                                                          charge: .calme,   issue: .adapte),
            .init(id: UUID(), date: jour(5), glycemie: 225, tendance: .stable,      glucides: nil, dose: 3, iob: nil, sport: nil,                                                          charge: .aucune,  issue: .insuffisant),
            .init(id: UUID(), date: jour(6), glycemie: 235, tendance: .forteHausse, glucides: nil, dose: 5, iob: nil, sport: nil,                                                          charge: .calme,   issue: .adapte),
            .init(id: UUID(), date: jour(7), glycemie: 240, tendance: .hausse,      glucides: nil, dose: 3, iob: nil, sport: nil,                                                          charge: .aucune,  issue: .insuffisant),
            .init(id: UUID(), date: jour(8), glycemie: 248, tendance: .stable,      glucides: 30,  dose: 6, iob: 1.0, sport: nil,                                                          charge: .moderee, issue: .surCorrection),
            .init(id: UUID(), date: jour(9), glycemie: 262, tendance: .forteHausse, glucides: nil, dose: 6, iob: nil, sport: nil,                                                          charge: .calme,   issue: .adapte),
        ]
        return AnalyseCorrections(corrections: corrections)
    }
}
