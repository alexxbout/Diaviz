//
//  TypeInsuline.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Type d'insuline injectée. Sert à la fois de discriminant métier
/// (lente vs rapide, repas vs correction) et de source d'attributs
/// visuels (taille de marqueur, couleur sémantique) consommés par
/// `GrapheJourneeMedications` et les listes de la page Médications.
nonisolated enum TypeInsuline: String, CaseIterable, Codable, Sendable {

    /// Insuline longue durée (ex: Lantus, Tresiba). Une injection
    /// par jour, à heure fixe ; pas de glycémie associée.
    case lente

    /// Insuline rapide injectée pour un repas. Saisie via la page
    /// Repas — ici en lecture seule.
    case rapideRepas

    /// Insuline rapide injectée pour corriger une hyperglycémie hors
    /// repas. La glycémie « avant » peut être renseignée manuellement
    /// (le CGM a un délai de 3h sur l'API Dexcom UE).
    case rapideCorrection

    // MARK: - Présentation visuelle

    /// Couleur sémantique du type — utilisée dans le graphe, les
    /// listes et la légende. Bleu pour la lente (stable, profond),
    /// violet pour les bolus repas (lien implicite avec la nourriture),
    /// orange pour les corrections (action ponctuelle).
    var couleur: Color {
        switch self {
        case .lente:             .blue
        case .rapideRepas:       .purple
        case .rapideCorrection:  .orange
        }
    }

    /// Taille du `PointMark` dans Swift Charts (aire en points²).
    /// Hiérarchie d'importance : la lente structure la journée,
    /// les repas sont fréquents, les corrections sont accessoires.
    var tailleMarqueur: Double {
        switch self {
        case .lente:             140
        case .rapideRepas:        90
        case .rapideCorrection:   55
        }
    }

    /// Libellé court utilisé dans la légende du graphe et les
    /// résumés (« 1 lente · 2 cor. · 2 repas »).
    var libelle: String {
        switch self {
        case .lente:             "Lente"
        case .rapideRepas:       "Repas"
        case .rapideCorrection:  "Correction"
        }
    }

    /// Libellé court pour le résumé du graphe (« 2 cor. »).
    var libelleAbrege: String {
        switch self {
        case .lente:             "lente"
        case .rapideRepas:       "repas"
        case .rapideCorrection:  "cor."
        }
    }
}
