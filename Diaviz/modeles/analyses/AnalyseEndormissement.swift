//
//  AnalyseEndormissement.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import Foundation

// MARK: - Issue d'une nuit en zones 1-2 (endormissement)

/// Ce qui s'est réellement passé à l'endormissement (zones 1-2, ≈ 2h après
/// la lente). Observation factuelle d'une nuit passée, pas une prédiction.
enum IssueEndormissement: Sendable, Equatable {

    /// Hypo survenue `delaiMinutes` minutes après la prise de lente.
    case hypo(delaiMinutes: Int)

    /// Pas d'hypo dans la fenêtre d'endormissement.
    case stable

    var estHypo: Bool {
        if case .hypo = self { return true }
        return false
    }
}

// MARK: - Une nuit analysée par B2

/// Une nuit dont la glycémie au coucher était **sous le seuil analysé**,
/// avec son contexte (sport, IOB) et son issue à l'endormissement.
///
/// Les champs contextuels sont des **tags neutres**, jamais des « coupables » :
/// c'est la mise en regard de toutes les nuits qui fait émerger le pattern,
/// pas une ligne isolée.
struct NuitEndormissement: Identifiable, Sendable, Equatable {

    let id: UUID
    let date: Date

    /// Glycémie (mg/dL) au moment de la prise de lente.
    let glycemieCoucher: Int

    /// Tendance de la glycémie au coucher (trajectoire).
    let tendance: TendanceGlycemie

    /// Glucides ingérés autour du coucher (g) — resucrage / collation.
    /// `nil` si aucun. Contexte clé : une nuit « stable » peut l'être
    /// **parce qu'**on a resucré, pas parce que la dose était juste.
    let glucides: Double?

    /// Séance de sport le jour même (détail au tap). `nil` si aucune.
    let sport: SportResume?

    /// IOB résiduel au coucher (unités). `nil` si nul.
    let iob: Double?

    /// Charge d'activité de la semaine glissante — contexte qui éclaire les
    /// hypos « inexpliquées » (sport non loggé ce soir mais semaine chargée).
    let charge: ChargeActivite

    let issue: IssueEndormissement
}

// MARK: - Snapshot B2

/// Snapshot prêt à afficher de l'analyse « Endormissement ».
/// `nuits` est triée par glycémie de coucher **croissante** : le risque se
/// concentre en haut, la lecture raconte l'histoire du plancher.
struct AnalyseEndormissement: Sendable, Equatable {

    /// Seuil de coucher analysé (mg/dL) — couchers au-dessus exclus.
    /// Provisoirement constant ; deviendra un réglage utilisateur.
    let seuilCoucher: Int

    /// Dose de lente actuelle (unités). Le tableau ne montre que les nuits
    /// **depuis le dernier changement de dose** → cette dose est commune à
    /// toutes les lignes, affichée une seule fois en en-tête.
    let doseActuelle: Double

    let nuits: [NuitEndormissement]

    var nombreHypos: Int {
        nuits.lazy.filter { $0.issue.estHypo }.count
    }
}
