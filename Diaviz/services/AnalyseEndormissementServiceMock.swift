//
//  AnalyseEndormissementServiceMock.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import Foundation

// MARK: - Issue d'une nuit en zones 1-2 (endormissement)

/// Ce qui s'est réellement passé à l'endormissement (zones 1-2, ≈ 2h après
/// la lente). Observation factuelle d'une nuit passée, pas une prédiction.
enum IssueEndormissement: Sendable, Equatable {

    /// Hypo survenue `delaiMinutes` minutes après la prise de lente.
    case hypo(delaiMinutes: Int)

    /// Pas d'hypo dans la fenêtre d'endormissement.
    case stable

    var estHypo: Bool {
        if case .hypo = self { return true }
        return false
    }
}

// MARK: - Une nuit analysée par B2

/// Une nuit dont la glycémie au coucher était **sous le seuil analysé**,
/// avec son contexte (sport, IOB) et son issue à l'endormissement.
///
/// Les champs contextuels sont des **tags neutres**, jamais des « coupables » :
/// c'est la mise en regard de toutes les nuits qui fait émerger le pattern,
/// pas une ligne isolée.
struct NuitEndormissement: Identifiable, Sendable, Equatable {

    let id: UUID
    let date: Date

    /// Glycémie (mg/dL) au moment de la prise de lente.
    let glycemieCoucher: Int

    /// Activité sportive le jour même (présence seule en V1).
    let sport: Bool

    /// IOB résiduel au coucher (unités). `nil` si nul.
    let iob: Double?

    /// Charge d'activité de la semaine glissante — contexte qui éclaire les
    /// hypos « inexpliquées » (sport non loggé ce soir mais semaine chargée).
    let charge: ChargeActivite

    let issue: IssueEndormissement
}

// MARK: - Snapshot B2

/// Snapshot prêt à afficher de l'analyse « Endormissement ».
/// `nuits` est triée par glycémie de coucher **croissante** : le risque se
/// concentre en haut, la lecture raconte l'histoire du plancher.
struct AnalyseEndormissement: Sendable, Equatable {

    /// Seuil de coucher analysé (mg/dL) — couchers au-dessus exclus.
    /// Provisoirement constant ; deviendra un réglage utilisateur.
    let seuilCoucher: Int

    /// Dose de lente actuelle (unités). Le tableau ne montre que les nuits
    /// **depuis le dernier changement de dose** → cette dose est commune à
    /// toutes les lignes, affichée une seule fois en en-tête.
    let doseActuelle: Double

    let nuits: [NuitEndormissement]

    var nombreHypos: Int {
        nuits.lazy.filter { $0.issue.estHypo }.count
    }
}

// MARK: - Mock

extension AnalyseEndormissement {

    /// Jeu typique : couchers sous 160, hypos concentrées en bas de l'échelle
    /// (dont une nuit « couché bas, aucun event → hypo quand même »).
    static var mock: AnalyseEndormissement {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        func jour(_ i: Int) -> Date { base.addingTimeInterval(Double(i) * 86_400) }

        let nuits: [NuitEndormissement] = [
            // Couché bas mais semaine off → stable. Le contraste avec la nuit
            // 112 (semaine intense → hypo) raconte le rôle de la charge.
            .init(id: UUID(), date: jour(0),  glycemieCoucher: 100, sport: false, iob: nil, charge: .aucune,  issue: .stable),
            .init(id: UUID(), date: jour(1),  glycemieCoucher: 105, sport: true,  iob: 1.5, charge: .moderee, issue: .hypo(delaiMinutes: 42)),
            .init(id: UUID(), date: jour(2),  glycemieCoucher: 112, sport: false, iob: nil, charge: .intense, issue: .hypo(delaiMinutes: 70)),
            .init(id: UUID(), date: jour(3),  glycemieCoucher: 116, sport: true,  iob: nil, charge: .moderee, issue: .hypo(delaiMinutes: 25)),
            .init(id: UUID(), date: jour(4),  glycemieCoucher: 121, sport: false, iob: 2.0, charge: .calme,   issue: .stable),
            .init(id: UUID(), date: jour(5),  glycemieCoucher: 124, sport: false, iob: nil, charge: .aucune,  issue: .stable),
            .init(id: UUID(), date: jour(6),  glycemieCoucher: 130, sport: true,  iob: nil, charge: .moderee, issue: .stable),
            .init(id: UUID(), date: jour(7),  glycemieCoucher: 134, sport: false, iob: nil, charge: .aucune,  issue: .stable),
            .init(id: UUID(), date: jour(8),  glycemieCoucher: 139, sport: false, iob: nil, charge: .calme,   issue: .stable),
            .init(id: UUID(), date: jour(9),  glycemieCoucher: 145, sport: true,  iob: nil, charge: .moderee, issue: .stable),
            .init(id: UUID(), date: jour(10), glycemieCoucher: 150, sport: false, iob: nil, charge: .aucune,  issue: .stable),
            .init(id: UUID(), date: jour(11), glycemieCoucher: 155, sport: false, iob: 1.0, charge: .calme,   issue: .stable),
            .init(id: UUID(), date: jour(12), glycemieCoucher: 158, sport: false, iob: nil, charge: .aucune,  issue: .stable),
        ]
        return AnalyseEndormissement(seuilCoucher: 160, doseActuelle: 18, nuits: nuits)
    }

    /// Aucune hypo récente — état rassurant.
    static var mockSansHypo: AnalyseEndormissement {
        let nuits = mock.nuits.map {
            NuitEndormissement(id: $0.id, date: $0.date,
                               glycemieCoucher: $0.glycemieCoucher,
                               sport: $0.sport, iob: $0.iob,
                               charge: $0.charge, issue: .stable)
        }
        return AnalyseEndormissement(seuilCoucher: 160, doseActuelle: 18, nuits: nuits)
    }
}
