//
//  PointCgm.swift
//  insulog
//
//  Created by Alexandre on 30/04/2026.
//

import Foundation

// MARK: - PointCgm
//
// Un échantillon de glycémie continu (CGM) rattaché à un repas.
// `secondesDepuisRepas` est négatif pour les points avant le repas (T-1h)
// et positif après (T+4h). On garde l'écart en secondes — pas en minutes —
// pour que le `Chart` puisse interpoler une ligne continue sans avoir
// à reconstruire un axe temporel.
struct PointCgm: Codable, Identifiable, Hashable, Sendable {
    /// Généré côté client : le backend envoie uniquement la donnée temps/valeur,
    /// l'identifiant sert seulement à `ForEach`/`Chart` côté SwiftUI.
    var id = UUID()
    let secondesDepuisRepas: TimeInterval
    let valeur: Double

    enum CodingKeys: String, CodingKey {
        case secondesDepuisRepas
        case valeur
    }
}
