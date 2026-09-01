//
//  ApercusInsightsAccueil.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

#if DEBUG

import Foundation

// MARK: - Aperçus individuels

extension Insight {

    /// Insight 1 — Impact du sport sur les ratios (informatif bleu).
    /// Donnée clé : « -25% » en grand chiffre bleu.
    static let mockImpactSport = Insight(
        id: UUID(),
        categorie: .informatif,
        titre: "Impact sport",
        message: "Impact sur vos ratios après musculation",
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

// MARK: - Catalogue d'aperçus

/// Source d'observations mockées de niveau accueil (aperçu ML) — distincte du
/// `InsightsService` historique qui sert la `RepasSheet` (insights
/// contextuels d'une saisie de repas).
///
/// **Volontairement non branché sur `AccueilVue`** (décision 2026-08-05) :
/// une fois de vraies observations disponibles (B1 `AnalyseBasaleService`,
/// R1 `AnalyseRatioService`), afficher en plus ces cartes factices à côté
/// était trompeur sur un écran de suivi de santé — impossible de distinguer
/// un vrai constat d'un exemple de mise en page. Le fichier reste en place
/// pour d'éventuelles previews/tests futurs (catalogue des 4 catégories
/// visuelles), mais `AccueilVue.insightsAffiches` ne lit plus `mockComplet()`.
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

#endif
