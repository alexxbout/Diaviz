//
//  TendanceGlycemie+HealthKit.swift
//  diaviz
//
//  Created by Alexandre on 15/06/2026.
//

import Foundation

extension TendanceGlycemie {
    /// Mappe la métadonnée Dexcom « Trend Arrow » (écrite dans HealthKit) vers
    /// les 5 états internes. Insensible à la casse. Valeurs non exploitables
    /// (`None`, `NotComputable`, `RateOutOfRange`, absente) → `nil`.
    init?(healthKitTrendArrow arrow: String?) {
        switch arrow?.lowercased() {
        case "doubleup":                   self = .forteHausse
        case "singleup", "fortyfiveup":    self = .hausse
        case "flat":                       self = .stable
        case "fortyfivedown", "singledown": self = .baisse
        case "doubledown":                 self = .forteBaisse
        default:                           return nil
        }
    }
}
