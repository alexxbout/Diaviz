//
//  Resucrage.swift
//  diaviz
//

import Foundation
import SwiftData

/// Une prise de glucides pour traiter ou prévenir une hypoglycémie —
/// **fait brut horodaté** du hub, décorrélé de tout repas et de toute
/// activité sportive au niveau du modèle (voir doc Eraser S1, décision du
/// 2026-08-06). Le rattachement à une activité, quand pertinent, se déduit
/// par fenêtre temporelle à l'affichage — jamais stocké ici (même principe
/// que `ActivitesSportService.reponse(pour:)` pour le CGM).
///
/// Distinct du flag `Aliment.resucrage` (déclaré *au sein* d'un repas) —
/// celui-ci reste pour ce cas précis, mais n'est plus le chemin principal.
@Model
final class Resucrage {
    var id: UUID
    /// Horodatage absolu de la prise (clé de tri / corrélation).
    var date: Date
    /// Pourquoi ce resucrage — obligatoire, jamais déduit (voir `IntentionResucrage`).
    var intention: IntentionResucrage
    /// Aliments pris — recherche aliment, même moteur que glucides pré-sport.
    @Relationship(deleteRule: .cascade) var aliments: [Aliment]
    /// Glycémie visée, seulement quand l'utilisateur cible une valeur
    /// précise. `nil` ≠ 0 — pas de cible par défaut implicite.
    var glycemieCible: Double?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        intention: IntentionResucrage,
        aliments: [Aliment] = [],
        glycemieCible: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.intention = intention
        self.aliments = aliments
        self.glycemieCible = glycemieCible
    }
}

extension Resucrage {
    /// Total des glucides pris (g), somme de `aliments`.
    var glucidesTotal: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }
}
