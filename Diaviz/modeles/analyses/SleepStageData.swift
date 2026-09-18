//
//  SleepStageData.swift
//  diaviz
//

import Foundation

/// Stade de sommeil pour l'overlay sur la courbe nocturne. Regroupe les
/// valeurs fines HealthKit (`asleepCore/Deep/REM/unspecified`) et retombe
/// sur `.asleepGenerique` quand seule la distinction basique asleep/awake
/// est disponible côté source (Watch ancienne génération, app tierce) —
/// overlay toujours factuel, jamais de stade inventé.
nonisolated enum SleepStage: Sendable, Equatable, Hashable {
    case awake
    case rem
    case core
    case deep
    /// Sommeil non différencié — seule granularité dispo sur certaines sources.
    case asleepGenerique
    case inBed

    /// Libellé factuel court pour le popover/légende.
    var label: String {
        switch self {
        case .awake:            return "Éveil"
        case .rem:               return "Paradoxal"
        case .core:              return "Léger"
        case .deep:               return "Profond"
        case .asleepGenerique:    return "Sommeil"
        case .inBed:              return "Au lit"
        }
    }
}

/// Un intervalle continu d'un même stade — unité de rendu de l'overlay
/// (une bande par intervalle).
nonisolated struct SleepStageInterval: Identifiable, Sendable {
    let id = UUID()
    let stage: SleepStage
    let debut: Date
    let fin: Date
}
