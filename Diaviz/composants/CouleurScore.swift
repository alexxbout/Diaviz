//
//  CouleurScore.swift
//  diaviz
//
//  Extrait de CarteScoreQuotidien.swift — aucune dépendance app, partagé
//  avec l'extension widget (empreinte glycémique).
//

import SwiftUI

/// Teinte continue alignée sur le mesh gradient : `hue` croît
/// linéairement de 0 (rouge, score 0) à 0.33 (vert, score 100). Le titre,
/// la dernière barre de l'historique et l'ombre du cercle (variante
/// sobre) utilisent tous cette même teinte pour rester raccord.
enum CouleurScore {
    static func hue(pour score: Int) -> Double {
        let borne = Double(min(100, max(0, score)))
        return (borne / 100.0) * 0.33
    }

    /// Couleur pleine d'accent — saturation/brightness calibrées pour
    /// rester lisibles en petit (titre 15pt, barre 5pt de large).
    static func couleur(pour score: Int) -> Color {
        Color(hue: hue(pour: score), saturation: 0.85, brightness: 0.80)
    }

    /// Variante continue pour une glycémie ponctuelle (mg/dL) plutôt qu'un
    /// score agrégé — utilisée par l'empreinte glycémique (`EmpreinteGlycemiqueVue`)
    /// pour teinter chaque point du nuage. Réutilise la même échelle de
    /// teinte que `couleur(pour:)` : en cible = vert (score équivalent
    /// élevé), hypo/hyper franches = rouge, en dégradé continu entre les
    /// deux — jamais de palier brutal.
    static func couleur(pourValeurGlycemie valeur: Int) -> Color {
        couleur(pour: scoreEquivalent(pourValeurGlycemie: valeur))
    }

    /// Score équivalent [5, 95] d'une glycémie ponctuelle : maximal sur toute
    /// la bande cible (70–180), puis décroît linéairement jusqu'aux bornes
    /// de clamp (40 / 300). Pas de vocation clinique — sert uniquement à
    /// réutiliser l'échelle de teinte existante pour un seul point.
    private static func scoreEquivalent(pourValeurGlycemie valeur: Int) -> Int {
        let clampBas = 40, clampHaut = 300, cibleBasse = 70, cibleHaute = 180
        let v = max(clampBas, min(clampHaut, valeur))
        guard v < cibleBasse || v > cibleHaute else { return 95 }
        let distance = v < cibleBasse
            ? Double(cibleBasse - v) / Double(cibleBasse - clampBas)
            : Double(v - cibleHaute) / Double(clampHaut - cibleHaute)
        return max(5, Int((95 - distance * 90).rounded()))
    }
}
