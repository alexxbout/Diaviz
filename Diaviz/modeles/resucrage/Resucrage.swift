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
/// Valeurs par défaut ci-dessous : filet de secours schema-only exigé par
/// CloudKit, jamais exercé par le flux normal — voir `GlucoseReading`.
@Model
final class Resucrage {
    var id: UUID = UUID()
    /// Horodatage absolu de la prise (clé de tri / corrélation).
    var date: Date = Date.distantPast
    /// Pourquoi ce resucrage — obligatoire, jamais déduit (voir `IntentionResucrage`).
    var intention: IntentionResucrage = IntentionResucrage.correctifHypo
    /// Stockage réel — **optionnel**, exigé par CloudKit pour toute relation
    /// (y compris à plusieurs). `aliments` ci-dessous en donne une vue
    /// non-optionnelle — voir le même pattern sur `Repas._aliments`.
    @Relationship(deleteRule: .cascade, inverse: \Aliment.resucrageParent) var _aliments: [Aliment]? = []

    /// Aliments pris — recherche aliment, même moteur que glucides pré-sport.
    var aliments: [Aliment] {
        get { _aliments ?? [] }
        set { _aliments = newValue }
    }
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
        self._aliments = aliments
        self.glycemieCible = glycemieCible
    }
}

extension Resucrage {
    /// Total des glucides pris (g), somme de `aliments`.
    var glucidesTotal: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }
}
