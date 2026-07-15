//
//  AlimentsCachesService.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import Foundation

/// Aliments CIQUAL masqués des suggestions (recherche + récents), persisté
/// dans UserDefaults. Uniquement CIQUAL — les produits Open Food Facts sont
/// déjà filtrés par la recherche explicite de l'utilisateur, masquer n'a de
/// sens que pour la base CIQUAL qui propose des correspondances automatiques.
@Observable
final class AlimentsCachesService {
    static let shared = AlimentsCachesService()

    private let cleStockage = "alimentsCachesCiqual"

    private(set) var idsCaches: Set<Int> = []

    private init() {
        charger()
    }

    // MARK: - API

    func cacher(_ id: Int) {
        idsCaches.insert(id)
        sauvegarder()
    }

    func demasquer(_ id: Int) {
        idsCaches.remove(id)
        sauvegarder()
    }

    func estCache(_ id: Int) -> Bool {
        idsCaches.contains(id)
    }

    /// Aliments masqués résolus depuis la base CIQUAL, triés par nom.
    var alimentsCaches: [AlimentCiqual] {
        CiqualService.shared.aliments
            .filter { idsCaches.contains($0.id) }
            .sorted { $0.nom < $1.nom }
    }

    // MARK: - Persistance

    private func charger() {
        if let ids = UserDefaults.standard.array(forKey: cleStockage) as? [Int] {
            idsCaches = Set(ids)
        }
    }

    private func sauvegarder() {
        UserDefaults.standard.set(Array(idsCaches), forKey: cleStockage)
    }
}
