//
//  InsightsAccueilServiceMock.swift
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

// MARK: - Mocks individuels (previews)

extension Insight {

    /// Insight 1 — Impact du sport sur les ratios (informatif bleu).
    /// Donnée clé : « -25% » en grand chiffre bleu.
    static let mockImpactSport = Insight(
        id: UUID(),
        categorie: .informatif,
        titre: "Impact sport",
        message: "Impact sur tes ratios après musculation",
        microVisuel: .grandNombre(valeur: "-25%"),
        lienAnalyse: "impact-sport"
    )

    /// Insight 2 — Pics récurrents au déjeuner malgré ratio habituel
    /// (attention orange). Mini bar chart : 4 déjeuners de la semaine,
    /// ligne horizontale grise à mi-hauteur (20pt sur 40pt) symbolise
    /// le seuil 200 mg/dL. Hauteurs [20, 28, 35, 24] → 3 barres
    /// dépassent strictement le seuil (cohérent avec le message).
    static let mockRatioMidi = Insight(
        id: UUID(),
        categorie: .attention,
        titre: "Ratios du midi",
        message: "3 pics > 200 cette semaine",
        microVisuel: .barres(hauteurs: [20, 28, 35, 24]),
        lienAnalyse: "ratios-midi"
    )

    /// Insight 3 — Nouvelle analyse cardio disponible (action violet).
    /// Donnée clé : grande icône `figure.run` violette — pas de chiffre
    /// à mettre en avant, l'icône résume le sujet.
    static let mockAnalyseCardio = Insight(
        id: UUID(),
        categorie: .action,
        titre: "Analyse cardio",
        message: "Nouvelle analyse disponible pour le cardio",
        microVisuel: .grandeIcone(systemName: "figure.run"),
        lienAnalyse: "analyse-cardio"
    )

    /// Insight 4 — Tendance nocturne à la baisse (attention orange).
    /// Donnée clé : « 3 nuits » en grand chiffre orange + flèche
    /// `arrow.down.right` indiquant la baisse.
    static let mockBasale = Insight(
        id: UUID(),
        categorie: .attention,
        titre: "Tendance nocturne",
        message: "Basale potentiellement trop élevée",
        microVisuel: .grandNombreAvecFleche(valeur: "3 nuits", direction: "arrow.down.right"),
        lienAnalyse: "tendance-nocturne"
    )
}

// MARK: - Service mock

/// Source d'observations affichées sur l'accueil. Pour le moment, ne
/// produit que des jeux mockés ; sera remplacé par une vraie source
/// (résultats ML pré-calculés) plus tard. L'API publique (`mockComplet`)
/// reste un tableau de `Insight` pour découpler la vue.
///
/// Distinct du `InsightsService` historique qui sert la `RepasSheet` :
/// celui-ci porte les observations de **niveau accueil** (aperçu ML),
/// pas les insights contextuels d'une saisie de repas.
enum InsightsAccueilServiceMock {

    /// Quatre observations couvrant les quatre catégories visuelles
    /// — utilisé par les previews et l'accueil en attendant la vraie
    /// source.
    static func mockComplet() -> [Insight] {
        [
            .mockImpactSport,
            .mockRatioMidi,
            .mockAnalyseCardio,
            .mockBasale,
        ]
    }
}

// MARK: - Persistance des suppressions

/// Persiste les identifiants d'insights supprimés par l'utilisateur (swipe /
/// appui long + confirmation dans `AccueilVue`) en UserDefaults. Suffisant
/// pour un simple ensemble d'UUID — pas de SwiftData nécessaire, ce n'est
/// qu'une préférence d'affichage, pas une donnée de santé.
enum InsightsAccueilPersistance {

    private nonisolated static let cle = "insightsAccueil.idsSupprimes"

    nonisolated static func chargerSupprimes() -> Set<UUID> {
        let chaines = UserDefaults.standard.stringArray(forKey: cle) ?? []
        return Set(chaines.compactMap(UUID.init(uuidString:)))
    }

    nonisolated static func sauvegarder(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: cle)
    }
}
