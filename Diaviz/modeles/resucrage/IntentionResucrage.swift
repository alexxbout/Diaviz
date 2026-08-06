//
//  IntentionResucrage.swift
//  diaviz
//

import SwiftUI

/// Intention déclarée d'un resucrage — obligatoire à la saisie (voir doc
/// Eraser S1, décision du 2026-08-06) : seul l'utilisateur connaît le
/// pourquoi, ça ne se déduit pas des données. Sert d'axe principal de
/// regroupement pour une future analyse (S1), jamais mélangée entre
/// intentions dans une même statistique.
enum IntentionResucrage: String, CaseIterable, Codable, Sendable, Hashable {
    /// Hypoglycémie confirmée (< 70 mg/dL) — traitement classique.
    case correctifHypo = "Correctif hypo"
    /// Effort long (aérobie) : petites prises répétées pour maintenir la
    /// glycémie en continu pendant l'activité, avant d'atteindre l'hypo.
    case preventifMaintien = "Préventif maintien"
    /// Effort court/anaérobie : dose modérée pour éviter une chute
    /// ponctuelle, sans viser un maintien prolongé.
    case preventifAntiChute = "Préventif anti-chute"

    var description: String {
        switch self {
        case .correctifHypo:       "Hypoglycémie confirmée, à traiter"
        case .preventifMaintien:   "Effort long — maintenir la glycémie en continu"
        case .preventifAntiChute:  "Éviter une chute ponctuelle, dose modérée"
        }
    }

    var icone: String {
        switch self {
        case .correctifHypo:       "exclamationmark.triangle.fill"
        case .preventifMaintien:   "arrow.left.arrow.right"
        case .preventifAntiChute:  "shield.lefthalf.filled"
        }
    }

    /// Couleur de l'icône — toujours teintée (pas seulement à la sélection)
    /// pour un scan visuel rapide entre les 3 cards, sur demande utilisateur.
    var couleur: Color {
        switch self {
        case .correctifHypo:       .red
        case .preventifMaintien:   .blue
        case .preventifAntiChute:  .orange
        }
    }
}
