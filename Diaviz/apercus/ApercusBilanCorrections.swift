//
//  ApercusBilanCorrections.swift
//  diaviz
//

#if DEBUG

import Foundation

// MARK: - Aperçus

extension BilanCorrections {

    /// Jeu typique : mix de résultats, quelques sur-corrections corrélées à
    /// un IOB résiduel, une tranche de dose faible en écart — et une poignée
    /// de corrections au repas pour exercer le picker de portée.
    static var mock: BilanCorrections {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        func heure(_ i: Int) -> Date { base.addingTimeInterval(Double(i) * 6 * 3600) }

        let isolees: [CorrectionEvaluee] = [
            .init(id: UUID(), date: heure(0), glycemie: 210, dose: 2, iobAvant: nil, picMax: 215, issue: .adapte, iobAuMomentHypo: nil, rechute: false, tranche: .doseProche, auRepas: false),
            .init(id: UUID(), date: heure(1), glycemie: 198, dose: 1.5, iobAvant: 0.8, picMax: 205, issue: .surCorrection, iobAuMomentHypo: 0.6, rechute: true, tranche: .doseNettementFaible, auRepas: false),
            .init(id: UUID(), date: heure(2), glycemie: 245, dose: 4, iobAvant: nil, picMax: 248, issue: .adapte, iobAuMomentHypo: nil, rechute: false, tranche: .doseProche, auRepas: false),
            .init(id: UUID(), date: heure(3), glycemie: 265, dose: 3, iobAvant: nil, picMax: 270, issue: .insuffisant, iobAuMomentHypo: nil, rechute: false, tranche: .doseNettementFaible, auRepas: false),
            .init(id: UUID(), date: heure(4), glycemie: 190, dose: 3, iobAvant: 1.1, picMax: 190, issue: .surCorrection, iobAuMomentHypo: 0.9, rechute: false, tranche: .doseNettementForte, auRepas: false),
            .init(id: UUID(), date: heure(5), glycemie: 225, dose: 3, iobAvant: nil, picMax: 228, issue: .adapte, iobAuMomentHypo: nil, rechute: false, tranche: .doseProche, auRepas: false),
            .init(id: UUID(), date: heure(6), glycemie: 255, dose: 5, iobAvant: nil, picMax: 258, issue: .adapte, iobAuMomentHypo: nil, rechute: false, tranche: .doseProche, auRepas: false),
        ]
        let bucketsIsolees: [BucketDoseCorrection] = [
            .init(tranche: .doseNettementFaible, total: 6, adaptees: 2),
            .init(tranche: .doseProche, total: 12, adaptees: 10),
        ]

        let auRepas: [CorrectionEvaluee] = [
            .init(id: UUID(), date: heure(7), glycemie: 220, dose: 3, iobAvant: nil, picMax: 240, issue: .adapte, iobAuMomentHypo: nil, rechute: false, tranche: nil, auRepas: true),
            .init(id: UUID(), date: heure(8), glycemie: 230, dose: 2, iobAvant: nil, picMax: 260, issue: .insuffisant, iobAuMomentHypo: nil, rechute: false, tranche: nil, auRepas: true),
            .init(id: UUID(), date: heure(9), glycemie: 205, dose: 2.5, iobAvant: nil, picMax: 215, issue: .adapte, iobAuMomentHypo: nil, rechute: false, tranche: nil, auRepas: true),
        ]

        return BilanCorrections(
            isolees: SousBilanCorrections(corrections: isolees, buckets: bucketsIsolees),
            auRepas: SousBilanCorrections(corrections: auRepas, buckets: [])
        )
    }
}

#endif
