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

/// Petit visuel optionnel placé entre le header et le message d'une
/// carte d'observation. Hauteur fixe ~30pt pour garder l'alignement
/// vertical des cartes au sein du TabView paginé (160pt).
///
/// Chaque cas est rendu par `MicroVisuelInsight` ; ajouter un nouveau
/// type de visuel consiste à étendre cet enum + son rendu.
enum MicroVisuelType: Sendable {
    /// Affiche `label → valeur` sur une ligne, valeur en .title3.bold().
    case pourcentage(label: String, valeur: String)
    /// Mini bar chart maison : barres verticales colorées dépassant
    /// une ligne horizontale grise (symbolise un seuil).
    case miniBarres(hauteurs: [CGFloat])
    /// Texte prefix + flèche SF Symbol + texte label coloré.
    case fleche(prefix: String, direction: String, label: String)
    /// Aucun visuel — le message prend plus d'espace vertical.
    case aucun
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
    static let mockImpactSport = Insight(
        id: UUID(),
        categorie: .informatif,
        titre: "Impact sport sur tes ratios",
        message: "Tes ratios sont impactés de -25% après tes séances de musculation cette semaine.",
        microVisuel: .pourcentage(label: "Ratio", valeur: "-25%"),
        lienAnalyse: "impact-sport"
    )

    /// Insight 2 — Pics récurrents au déjeuner malgré ratio habituel
    /// (attention orange). Le mini bar chart symbolise 4 déjeuners de
    /// la semaine et le seuil 200 mg/dL en ligne grise. Hauteurs
    /// calibrées pour tenir dans une frame de 30pt (max 28pt = peek
    /// de 10pt au-dessus du seuil tracé à y:-18).
    static let mockRatioMidi = Insight(
        id: UUID(),
        categorie: .attention,
        titre: "Ratios du midi",
        message: "3 déjeuners cette semaine ont généré un pic malgré le ratio habituel.",
        microVisuel: .miniBarres(hauteurs: [24, 18, 28, 22]),
        lienAnalyse: "ratios-midi"
    )

    /// Insight 3 — Nouvelle analyse cardio disponible (action violet).
    /// Pas de micro-visuel : le message prend toute la place.
    static let mockAnalyseCardio = Insight(
        id: UUID(),
        categorie: .action,
        titre: "Analyse cardio",
        message: "Nouvelle analyse disponible : ta réponse glycémique au cardio a évolué depuis 2 semaines.",
        microVisuel: .aucun,
        lienAnalyse: "analyse-cardio"
    )

    /// Insight 4 — Tendance nocturne à la baisse (attention orange).
    static let mockBasale = Insight(
        id: UUID(),
        categorie: .attention,
        titre: "Tendance nocturne",
        message: "Tendance à la baisse détectée sur 3 nuits. Ta basale pourrait être trop élevée.",
        microVisuel: .fleche(prefix: "3 nuits", direction: "arrow.down.right", label: "↘ tendance basse"),
        lienAnalyse: "tendance-nocturne"
    )
}

// MARK: - Service mock

/// Source d'observations affichées sur l'accueil. Pour le moment, ne
/// produit que des jeux mockés ; sera remplacé par une vraie source
/// (résultats ML pré-calculés) plus tard. L'API publique (`mockComplet`,
/// `mockVide`) reste un tableau de `Insight` pour découpler la vue.
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

    /// État neutre — la section d'observations est alors masquée.
    static func mockVide() -> [Insight] { [] }
}
