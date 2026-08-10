//
//  ApercusAnalyseCorrections.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

#if DEBUG

import Foundation

// MARK: - Aperçus

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

#endif
