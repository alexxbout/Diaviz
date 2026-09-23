//
//  ApercusAnalyseEndormissement.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

#if DEBUG

import Foundation

// MARK: - Aperçus

extension AnalyseEndormissement {

    /// Jeu typique : couchers sous 160, hypos concentrées en bas de l'échelle
    /// (dont une nuit « couché bas, aucun event → hypo quand même »).
    static var mock: AnalyseEndormissement {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        func jour(_ i: Int) -> Date { base.addingTimeInterval(Double(i) * 86_400) }

        let nuits: [NuitEndormissement] = [
            // Couché bas mais semaine off → stable. Le contraste avec la nuit
            // 112 (semaine intense → hypo) raconte le rôle de la charge.
            .init(id: UUID(), date: jour(0),  glycemieCoucher: 100, tendance: .stable,      glucides: 10,  sport: nil,                                                          iob: nil, charge: nil,  issue: .stable),
            .init(id: UUID(), date: jour(1),  glycemieCoucher: 105, tendance: .baisse,      glucides: 15,  sport: SportResume(type: "Course", intensite: "modéré", dureeMinutes: 45), iob: 1.5, charge: .normale, issue: .hypo(delaiMinutes: 42)),
            .init(id: UUID(), date: jour(2),  glycemieCoucher: 112, tendance: .forteBaisse, glucides: 20,  sport: nil,                                                          iob: nil, charge: .haute, issue: .hypo(delaiMinutes: 70)),
            .init(id: UUID(), date: jour(3),  glycemieCoucher: 116, tendance: .baisse,      glucides: nil, sport: SportResume(type: "Vélo", intensite: "intense", dureeMinutes: 60), iob: nil, charge: .normale, issue: .hypo(delaiMinutes: 25)),
            .init(id: UUID(), date: jour(4),  glycemieCoucher: 121, tendance: .stable,      glucides: nil, sport: nil,                                                          iob: 2.0, charge: .normale,   issue: .stable),
            .init(id: UUID(), date: jour(5),  glycemieCoucher: 124, tendance: .hausse,      glucides: nil, sport: nil,                                                          iob: nil, charge: nil,  issue: .stable),
            .init(id: UUID(), date: jour(6),  glycemieCoucher: 130, tendance: .stable,      glucides: nil, sport: SportResume(type: "Marche", intensite: "léger", dureeMinutes: 30), iob: nil, charge: .normale, issue: .stable),
            .init(id: UUID(), date: jour(7),  glycemieCoucher: 134, tendance: .stable,      glucides: nil, sport: nil,                                                          iob: nil, charge: nil,  issue: .stable),
            .init(id: UUID(), date: jour(8),  glycemieCoucher: 139, tendance: .hausse,      glucides: nil, sport: nil,                                                          iob: nil, charge: .normale,   issue: .stable),
            .init(id: UUID(), date: jour(9),  glycemieCoucher: 145, tendance: .stable,      glucides: nil, sport: SportResume(type: "Course", intensite: "modéré", dureeMinutes: 40), iob: nil, charge: .normale, issue: .stable),
            .init(id: UUID(), date: jour(10), glycemieCoucher: 150, tendance: .stable,      glucides: nil, sport: nil,                                                          iob: nil, charge: nil,  issue: .stable),
            .init(id: UUID(), date: jour(11), glycemieCoucher: 155, tendance: .baisse,      glucides: nil, sport: nil,                                                          iob: 1.0, charge: .normale,   issue: .stable),
            .init(id: UUID(), date: jour(12), glycemieCoucher: 158, tendance: .stable,      glucides: nil, sport: nil,                                                          iob: nil, charge: nil,  issue: .stable),
        ]
        return AnalyseEndormissement(seuilCoucher: 160, doseActuelle: 18, nuits: nuits)
    }

    /// Aucune hypo récente — état rassurant.
    static var mockSansHypo: AnalyseEndormissement {
        let nuits = mock.nuits.map {
            NuitEndormissement(id: $0.id, date: $0.date,
                               glycemieCoucher: $0.glycemieCoucher,
                               tendance: $0.tendance, glucides: $0.glucides,
                               sport: $0.sport, iob: $0.iob,
                               charge: $0.charge, issue: .stable)
        }
        return AnalyseEndormissement(seuilCoucher: 160, doseActuelle: 18, nuits: nuits)
    }
}

#endif
