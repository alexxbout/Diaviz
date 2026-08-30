//
//  AlimentsCachesService.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import Foundation
import SwiftData

/// Aliments CIQUAL masqués des suggestions (recherche + récents). Uniquement
/// CIQUAL — les produits Open Food Facts sont déjà filtrés par la recherche
/// explicite de l'utilisateur, masquer n'a de sens que pour la base CIQUAL
/// qui propose des correspondances automatiques.
///
/// Persisté dans le hub SwiftData (`PreferenceAlimentCiqual`, partagé avec
/// `NomsPersonnalisesService`), donc synchronisé par CloudKit. L'état reste
/// en mémoire pour la lecture : `estCache` est appelé sur chaque ligne de
/// résultat de recherche, un fetch à chaque appel serait absurde.
@Observable
final class AlimentsCachesService {
    static let shared = AlimentsCachesService()

    private(set) var idsCaches: Set<Int> = []

    private var contexte: ModelContext?

    private init() {}

    /// Branche le service sur le hub et charge l'état. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    /// Recharge depuis le store — appelé après un import CloudKit.
    func recharger() {
        guard let contexte else { return }
        let lignes = (try? contexte.fetch(FetchDescriptor<PreferenceAlimentCiqual>())) ?? []
        idsCaches = Set(lignes.filter(\.masque).map(\.idCiqual))
    }

    // MARK: - API

    func cacher(_ id: Int) {
        idsCaches.insert(id)
        PreferencesAlimentsStockage.modifier(id, contexte: contexte) { $0.masque = true }
        ToastsService.shared.afficher(
            .reglage,
            titre: "Aliment masqué",
            detail: "Il ne remontera plus dans la recherche",
            action: ActionToast(libelle: "Annuler") { [weak self] in self?.demasquer(id) }
        )
    }

    func demasquer(_ id: Int) {
        idsCaches.remove(id)
        PreferencesAlimentsStockage.modifier(id, contexte: contexte) { $0.masque = false }
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
}
