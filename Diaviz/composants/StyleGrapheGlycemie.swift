//
//  StyleGrapheGlycemie.swift
//  diaviz
//

import Charts
import SwiftUI

/// Peau commune à tous les graphiques de glycémie de l'app — repas, sport,
/// médications, analyse du coucher.
///
/// Ces graphiques ne partagent pas leur code : `GraphiqueGlycemique` sert les
/// pages repas et sport, tandis que l'analyse basale a le sien (zones de nuit,
/// crosshair, pills tappables — des mécanismes qui n'existent nulle part
/// ailleurs). Fusionner les deux reviendrait à gonfler le composant partagé
/// pour un seul appelant, ou à faire perdre ses fonctionnalités à B1.
///
/// D'où ce fichier : ce qui doit se **ressembler** (épaisseurs, pointillés,
/// opacités, teintes de seuil) vit ici, ce qui diffère reste chez chacun.
/// Avant, chaque graphique redéfinissait ses propres valeurs et l'écart se
/// voyait : bande de cible présente d'un côté et pas de l'autre, courbe à
/// 2 pt contre 2,5, pointillés `[4,4]` contre `[3,3]`.
nonisolated enum StyleGrapheGlycemie {

    // MARK: Traits

    /// Épaisseur de la courbe principale.
    static let epaisseurCourbe: CGFloat = 2
    /// Épaisseur d'une courbe secondaire (moyenne, comparaison).
    static let epaisseurCourbeSecondaire: CGFloat = 1.5
    /// Épaisseur des lignes de seuil (hypo / hyper).
    static let epaisseurSeuil: CGFloat = 1
    /// Épaisseur des lignes de grille.
    static let epaisseurGrille: CGFloat = 0.5

    /// Pointillés des lignes de seuil.
    static let pointillesSeuil: [CGFloat] = [4, 4]
    /// Pointillés de la grille.
    static let pointillesGrille: [CGFloat] = [4, 4]

    static var traitSeuil: StrokeStyle {
        StrokeStyle(lineWidth: epaisseurSeuil, dash: pointillesSeuil)
    }
    static var traitGrille: StrokeStyle {
        StrokeStyle(lineWidth: epaisseurGrille, dash: pointillesGrille)
    }

    // MARK: Teintes

    /// Bande de la zone cible — assez pâle pour passer sous la courbe.
    static let opaciteZoneCible: Double = 0.08
    /// Bandeau d'une fenêtre de contexte (effort sportif, zone de nuit).
    static let opaciteZoneContexte: Double = 0.06
    /// Opacité des lignes de seuil : présentes, jamais dominantes.
    static let opaciteSeuil: Double = 0.5

    static let couleurSeuilBas = Color.red
    static let couleurSeuilHaut = Color.orange
    static let couleurZoneCible = Color.green

    // MARK: Gabarit

    /// Hauteur d'un graphique pleine largeur.
    static let hauteur: CGFloat = 220
    /// Hauteur d'une mini-courbe (carte d'accueil, ligne de liste).
    static let hauteurMini: CGFloat = 90
    /// Police des labels d'axe.
    static let policeAxe: Font = .caption2
}

// MARK: - Marks partagés

extension StyleGrapheGlycemie {

    /// Bande de la zone cible, bornée par les seuils du profil. Les seuils
    /// sont lus ici et non passés en paramètre : ils sont les mêmes pour toute
    /// l'app, et un graphique qui les recodait en dur (l'analyse basale le
    /// faisait, avec 70 et 180 figés) ne suivait pas les réglages.
    @ChartContentBuilder
    static func zoneCible<X: Plottable>(
        de debut: X, a fin: X,
        seuils: SeuilsGlycemiques
    ) -> some ChartContent {
        RectangleMark(
            xStart: .value("Début", debut),
            xEnd: .value("Fin", fin),
            yStart: .value("Cible bas", seuils.hypoglycemie),
            yEnd: .value("Cible haut", seuils.hyperglycemie)
        )
        .foregroundStyle(couleurZoneCible.opacity(opaciteZoneCible))
    }

    /// Les deux lignes de seuil, dans le style commun.
    @ChartContentBuilder
    static func lignesSeuils(_ seuils: SeuilsGlycemiques) -> some ChartContent {
        RuleMark(y: .value("Hypo", seuils.hypoglycemie))
            .foregroundStyle(couleurSeuilBas.opacity(opaciteSeuil))
            .lineStyle(traitSeuil)
        RuleMark(y: .value("Hyper", seuils.hyperglycemie))
            .foregroundStyle(couleurSeuilHaut.opacity(opaciteSeuil))
            .lineStyle(traitSeuil)
    }
}
