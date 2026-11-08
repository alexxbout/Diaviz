//
//  StructureEffort.swift
//  diaviz
//

import Foundation

/// Structure de l'effort pendant une activité cardio — continu (allure
/// régulière) ou fractionné (alternance d'intensité, intervalles).
///
/// Pertinent uniquement pour `CategorieSport.cardio` (course, vélo,
/// natation, marche, sport collectif) — `nil` pour musculation/yoga/autre.
/// Distinction cliniquement significative (littérature ISPAD 2022 : la
/// chute glycémique en exercice mixte/intervalles diffère de l'aérobie
/// continu), retenue lors du cadrage de l'analyse S1 (2026-08-06).
nonisolated enum StructureEffort: String, CaseIterable, Codable, Sendable, Hashable {
    case continu = "Continu"
    case fractionne = "Fractionné"

    /// Description courte affichée en sous-titre des cards radio de la
    /// sheet de saisie — même registre que `IntensiteSport.description`.
    var description: String {
        switch self {
        case .continu:    "Allure régulière, effort stable"
        case .fractionne: "Alternance d'intensité, intervalles"
        }
    }
}
