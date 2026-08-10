//
//  CourbeNuit.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation

// MARK: - Fenêtre d'analyse

/// Fenêtre clinique standard pour évaluer un changement de dose de
/// basale — 14 nuits. C'est le minimum recommandé par la littérature
/// pour qu'un verdict de tendance soit fiable, sans être si long que
/// les ajustements récents soient masqués par l'historique.
///
/// La page n'expose plus de picker 7/14/30 jours : on travaille
/// toujours sur 14 nuits glissantes, mais une **timeline visuelle**
/// (`TimelineNuitsVue`) montre lesquelles sont valides et pourquoi les
/// autres sont exclues.
let kFenetreNuits: Int = 14

// MARK: - Modèles de courbe nocturne

/// Un point d'une courbe glycémique nocturne — heure exprimée en
/// **heures depuis 00h** (0.0 → 6.0) pour rester indépendant d'une date
/// calendaire spécifique. Sert à la fois à `Chart` (axe X numérique)
/// et au calcul de la tendance moyenne (interpolation simple par index).
nonisolated struct PointCourbeNuit: Identifiable, Equatable, Sendable {
    let id = UUID()
    let heure: Double
    let valeur: Double

    static func == (lhs: PointCourbeNuit, rhs: PointCourbeNuit) -> Bool {
        lhs.heure == rhs.heure && lhs.valeur == rhs.valeur
    }
}

/// Catégorisation d'une nuit **valide** pour la répartition.
nonisolated enum CategorieNuit: Sendable {
    case stable
    case tendanceBasse
    case tendanceHaute
}

/// Une nuit individuelle valide — sa série de points + sa catégorie +
/// ses éventuels points hypos (< 70 mg/dL) à afficher en rouge.
nonisolated struct CourbeNuit: Identifiable, Sendable {
    let id = UUID()
    let categorie: CategorieNuit
    let points: [PointCourbeNuit]

    /// Points où la valeur passe sous 70 — extraits une seule fois à la
    /// construction pour éviter de re-filtrer à chaque render du chart.
    var pointsHypo: [PointCourbeNuit] {
        points.filter { $0.valeur < 70 }
    }
}
