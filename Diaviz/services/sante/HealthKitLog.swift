//
//  HealthKitLog.swift
//  diaviz
//
//  Created by Alexandre on 15/06/2026.
//

import OSLog

nonisolated extension Logger {
    /// Journal du sous-système HealthKit (autorisation, lecture glycémie,
    /// ingestion). Filtrer sur la catégorie « HealthKit ».
    static let sante = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "fr.al3xdre.diaviz",
        category: "HealthKit"
    )
}
