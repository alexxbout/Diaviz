//
//  RepasARevoirMasquesService.swift
//  diaviz
//

import Foundation

/// Repas « à revoir » masqués par l'utilisateur (long press → confirmation),
/// persisté dans UserDefaults. Même pattern que `AlimentsCachesService`.
///
/// Masque par **occurrence précise** (`RepasARevoir.idRepasSource`, l'id du
/// vrai `Repas` SwiftData qui a motivé la carte), jamais par groupe/signature :
/// si ce même repas se reproduit avec un nouveau mauvais résultat, le
/// "dernier" du groupe devient un nouveau `Repas` (nouvel id, absent de ce
/// set) et la carte réapparaît d'elle-même — voir `CalculRepasARevoir.analyser`.
@Observable
final class RepasARevoirMasquesService {
    static let shared = RepasARevoirMasquesService()

    private let cleStockage = "repasARevoirMasques"

    private(set) var idsMasques: Set<UUID> = []

    private init() {
        charger()
    }

    // MARK: - API

    func masquer(_ id: UUID) {
        idsMasques.insert(id)
        sauvegarder()
    }

    /// Réglages → « Supprimer les repas masqués ». Volontairement pas de
    /// liste consultable (pas demandé) : juste un reset global.
    func toutDemasquer() {
        idsMasques = []
        sauvegarder()
    }

    // MARK: - Persistance

    private func charger() {
        guard let chaines = UserDefaults.standard.array(forKey: cleStockage) as? [String] else { return }
        idsMasques = Set(chaines.compactMap(UUID.init))
    }

    private func sauvegarder() {
        UserDefaults.standard.set(idsMasques.map(\.uuidString), forKey: cleStockage)
    }
}
