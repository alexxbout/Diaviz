//
//  Insight.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

// MARK: - Catégories

/// Catégorie visuelle d'une observation ML affichée sur l'accueil.
/// Pilote la couleur d'accent et l'icône SF Symbol associée à la carte.
///
/// Quatre catégories — chacune répond à un type d'observation
/// différent que la couche ML pourra produire :
///   - `positif` : un pattern qui marche bien (ratio cohérent, TIR stable)
///   - `attention` : une dérive ou un signal à surveiller
///   - `informatif` : un constat factuel sans charge émotionnelle
///   - `action` : une nouvelle analyse disponible à consulter
///
/// Aucune catégorie ne **prescrit** d'action de soin — toutes restent
/// descriptives, conformément aux principes de l'app.
enum CategorieInsight: String, CaseIterable, Sendable {
    case positif
    case attention
    case informatif
    case action

    /// Couleur d'accent appliquée à l'icône, au tint du glassEffect et
    /// au lien « Voir l'analyse → ».
    var couleur: Color {
        switch self {
        case .positif: return .green
        case .attention: return .orange
        case .informatif: return .blue
        case .action: return .purple
        }
    }

    /// Icône SF Symbol affichée à gauche du titre dans le header.
    var icone: String {
        switch self {
        case .positif: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .informatif: return "info.circle.fill"
        case .action: return "sparkles"
        }
    }
}

// MARK: - Micro-visuel

/// **Donnée clé** d'une carte d'observation — l'élément dominant visuel,
/// centré dans la carte, à la couleur de la catégorie. Hauteur cible
/// 40pt pour ancrer la hiérarchie (titre `.caption` au-dessus, message
/// `.callout` en dessous).
///
/// Chaque cas est rendu par `MicroVisuelInsight` ; ajouter un nouveau
/// type de visuel consiste à étendre cet enum + son rendu.
enum MicroVisuelType: Sendable {
    /// Grand chiffre seul — 40pt bold à la couleur de la catégorie.
    /// Pour les insights où la donnée clé est une valeur unique
    /// (« -25% », « +12 », « x2 »…).
    case grandNombre(valeur: String)
    /// Grand chiffre + flèche directionnelle SF Symbol — pour exprimer
    /// une tendance chiffrée (« 3 nuits ↘ »). Chiffre 40pt bold,
    /// flèche `.title`, tous deux à la couleur de la catégorie.
    case grandNombreAvecFleche(valeur: String, direction: String)
    /// Mini bar chart — 4 barres verticales 12pt × hauteur, dans un
    /// conteneur 40pt, traversées par une ligne horizontale grise à
    /// mi-hauteur (seuil ~200 mg/dL). Hauteurs > 20 dépassent le seuil.
    case barres(hauteurs: [CGFloat])
    /// Grande icône SF Symbol — 36pt à la couleur de la catégorie.
    /// Pour les insights sans donnée chiffrée (ex : nouvelle analyse
    /// disponible) où l'icône résume à elle seule le sujet.
    case grandeIcone(systemName: String)
}

// MARK: - Modèle

/// Observation produite par la couche ML et affichée comme aperçu sur
/// l'accueil. Le détail complet vit sur la page Analyses ; ici on ne
/// montre qu'un résumé + un lien.
///
/// Restera identique quand la vraie source remplacera le mock — seul
/// `InsightsAccueilServiceMock` changera.
struct Insight: Identifiable, Sendable {
    let id: UUID
    let categorie: CategorieInsight
    let titre: String
    let message: String
    let microVisuel: MicroVisuelType
    /// Identifiant de l'analyse cible quand on saura router vers la
    /// page Analyses. `nil` = pas de lien (le bouton « Voir l'analyse
    /// → » reste visible mais inactif).
    let lienAnalyse: String?
}

