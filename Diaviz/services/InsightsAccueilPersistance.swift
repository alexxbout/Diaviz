//
//  InsightsAccueilPersistance.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import Foundation

// MARK: - Persistance des suppressions

/// Persiste les identifiants d'insights supprimés par l'utilisateur (swipe /
/// appui long + confirmation dans `AccueilVue`) en UserDefaults. Suffisant
/// pour un simple ensemble d'UUID — pas de SwiftData nécessaire, ce n'est
/// qu'une préférence d'affichage, pas une donnée de santé.
enum InsightsAccueilPersistance {

    private nonisolated static let cle = "insightsAccueil.idsSupprimes"

    nonisolated static func chargerSupprimes() -> Set<UUID> {
        let chaines = UserDefaults.standard.stringArray(forKey: cle) ?? []
        return Set(chaines.compactMap(UUID.init(uuidString:)))
    }

    nonisolated static func sauvegarder(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: cle)
    }
}
