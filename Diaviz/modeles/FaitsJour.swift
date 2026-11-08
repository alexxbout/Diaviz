//
//  FaitsJour.swift
//  diaviz
//
//  Created by Alexandre on 06/05/2026.
//

import Foundation

/// Métriques agrégées d'une journée.
///
/// Toutes les unités sont en pourcentage sauf `score` (0–100), `hypoCount`,
/// `severeHypoCount` (entiers), et `peakValue` (mg/dL).
nonisolated struct FaitsJour: Sendable, Equatable, Hashable {
    let score: Int
    let tir: Double
    let tbrLevel1: Double
    let tbrLevel2: Double
    let tarLevel1: Double
    let tarLevel2: Double
    let hypoCount: Int
    let severeHypoCount: Int
    let peakTime: String?
    let peakValue: Int?
    let mealContext: String?
    let sportContext: String?
}
