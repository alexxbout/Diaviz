//
//  BarreAGP.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Barre AGP segmentée

/// Barre horizontale segmentée pleine largeur — résume la répartition
/// du temps sur 24 h dans **3 zones glycémiques agrégées** :
///
///   - Hypo (rouge #E24B4A) — somme `tbrLevel2 + tbrLevel1` (< 70 mg/dL)
///   - En cible (vert #1D9E75) — `tir` (70–180 mg/dL)
///   - Hyper (orange #EF9F27) — somme `tarLevel1 + tarLevel2` (> 180 mg/dL)
///
/// Le détail à 5 zones (sévère / non-sévère) reste consultable dans
/// la section DÉCOMPOSITION juste en dessous — ici on agrège pour un
/// résumé lisible d'un coup d'œil.
///
/// Largeur de chaque segment proportionnelle à son pourcentage. Le
/// pourcentage est rendu en blanc centré dans le segment, à une taille
/// qui s'adapte à la largeur disponible :
///   - ≥ 15 % → `.caption` bold (largement lisible)
///   - 5–14 % → `.caption2` (compact mais lisible)
///   - < 5 % → pas de texte (sinon illisible), segment rendu en trait fin
///
/// Les coins de la barre sont arrondis via un `clipShape` global
/// (8 pt) — les segments individuels ne sont pas arrondis, c'est le
/// clip qui dessine les arrondis aux extrémités.
struct BarreAGP: View {

    let faits: FaitsJour

    var body: some View {
        // Couleurs système iOS — alignées sur celles utilisées par la
        // section DÉCOMPOSITION juste en dessous (`.red` pour la row
        // Hypo, `.green` pour Temps en cible, `.orange` pour Hyper).
        // Apple les a calibrées pour fonctionner ensemble : même
        // niveau de vivacité, accessibilité Dynamic Color (mode clair
        // / sombre, contraste élevé) gérée automatiquement.
        BarreSegments3(segments: [
            SegmentBarre(couleur: .green, valeur: faits.tir),
            SegmentBarre(couleur: .orange, valeur: faits.tarLevel1 + faits.tarLevel2),
            SegmentBarre(couleur: .red, valeur: faits.tbrLevel2 + faits.tbrLevel1),
        ])
        .accessibilityElement()
        .accessibilityLabel(libelleAccessibilite)
    }

    private var libelleAccessibilite: String {
        let pctHypo = faits.tbrLevel2 + faits.tbrLevel1
        let pctHyper = faits.tarLevel1 + faits.tarLevel2
        let lignes: [(String, Double)] = [
            ("Hypo", pctHypo),
            ("En cible", faits.tir),
            ("Hyper", pctHyper),
        ]
        return lignes
            .map { String(format: "%@ %.0f pour cent", $0.0, $0.1) }
            .joined(separator: ", ")
    }
}
