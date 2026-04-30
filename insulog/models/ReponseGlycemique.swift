//
//  ReponseGlycemique.swift
//  insulog
//
//  Created by Alexandre on 30/04/2026.
//

import SwiftUI

// MARK: - VerdictGlycemique (extension)
//
// L'enum `VerdictGlycemique` est défini dans `RepasGraph.swift` avec ses
// conformances (`Hashable, Codable, Sendable`) — la synthèse automatique
// de `Codable` exige que la conformance soit déclarée dans le fichier de
// l'enum. On l'enrichit ici uniquement avec la description VoiceOver
// spécifique à la mini-courbe.

extension VerdictGlycemique {
    /// Description textuelle utilisée pour l'accessibilité (VoiceOver) sur
    /// la mini-courbe — reformulation phrasée plutôt qu'un simple libellé.
    var descriptionAccessibilite: String {
        switch self {
        case .bon: return "Réponse glycémique bonne"
        case .moyen: return "Réponse glycémique moyenne"
        case .mauvais: return "Réponse glycémique mauvaise"
        case .indetermine: return "Réponse glycémique indéterminée"
        }
    }
}

// MARK: - ReponseGlycemique
//
// Photographie complète de la réponse post-repas (T-1h à T+4h).
// Pré-calculé côté backend : l'app n'a qu'à afficher.
struct ReponseGlycemique: Codable, Sendable {
    /// Échantillons CGM normalisés autour de T0 (l'heure du repas).
    let pointsCgm: [PointCgm]
    let verdict: VerdictGlycemique
    /// Glycémie maximale observée après le repas (mg/dL).
    let valeurPic: Double
    /// Délai entre le repas et le pic (en secondes). Aligné sur l'un
    /// des `secondesDepuisRepas` de `pointsCgm` pour que le marqueur
    /// PointMark tombe exactement sur la courbe.
    let tempsPic: TimeInterval
    /// Délai avant retour dans la cible (≤ 180 mg/dL). `nil` si la
    /// glycémie n'est jamais redescendue dans la fenêtre observée.
    let tempsRetourCible: TimeInterval?
}
