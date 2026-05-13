//
//  CategorieSport.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Catégorie de sport agrégée. Regroupe les `TypeSport` apparentés pour
/// la coloration sémantique du graphe (timeline du jour) et la légende.
///
/// Trois catégories — choix volontairement réduit pour que la légende
/// reste lisible (pattern identique aux 3 types d'insuline du graphe
/// Médications). Chaque catégorie a une couleur stable, que tous les
/// types qui en relèvent partagent.
enum CategorieSport: String, Codable, Sendable, CaseIterable, Hashable {

    /// Effort cardiovasculaire — course, vélo, natation, marche, sport
    /// collectif. Impact glycémique typiquement **descendant** pendant
    /// l'effort.
    case cardio

    /// Travail en force — musculation au sens large. Impact glycémique
    /// plus variable (peut faire monter pendant l'effort intense).
    case musculation

    /// Activité douce ou non classifiée — yoga, autre. Impact glycémique
    /// souvent **stable**.
    case autre

    // MARK: - Présentation

    /// Couleur sémantique de la catégorie — utilisée par le graphe, la
    /// légende et la mini-courbe de la row. Cohérente avec la palette
    /// système iOS pour adaptation auto Dark Mode et Increase Contrast.
    var couleur: Color {
        switch self {
        case .cardio:        .red
        case .musculation:   .purple
        case .autre:         .blue
        }
    }

    /// Libellé court affiché dans la légende sous le graphe et dans le
    /// résumé compact en en-tête (« 1 cardio · 1 autre »).
    var libelle: String {
        switch self {
        case .cardio:        "Cardio"
        case .musculation:   "Musculation"
        case .autre:         "Autre"
        }
    }
}
