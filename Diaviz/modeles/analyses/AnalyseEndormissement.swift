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
nonisolated enum IssueEndormissement: Sendable, Equatable {

    /// Hypo survenue `delaiMinutes` minutes après la prise de lente.
    /// Couvre aussi le cas d'un resucrage **correctif** loggé sans creux CGM
    /// visible : l'utilisateur a confirmé l'hypo, le capteur l'a manquée.
    case hypo(delaiMinutes: Int)

    /// Resucrage **préventif** pris dans la fenêtre de coucher, sans passage
    /// sous le seuil. Ni hypo (la glycémie n'est jamais descendue), ni stable
    /// (l'utilisateur a dû intervenir) — sans cet état, les soirs « rien fait,
    /// rien passé » et « resucré donc rien passé » se confondaient, et le plus
    /// instructif des deux disparaissait. Hors du compteur d'hypos.
    case hypoEvitee(glucides: Int)

    /// Pas d'hypo dans la fenêtre d'endormissement, aucune intervention.
    case stable

    var estHypo: Bool {
        if case .hypo = self { return true }
        return false
    }

    var estHypoEvitee: Bool {
        if case .hypoEvitee = self { return true }
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
nonisolated struct NuitEndormissement: Identifiable, Sendable, Equatable {

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

    /// Niveau de charge active du jour — contexte qui éclaire les hypos
    /// « inexpliquées » (sport non loggé ce soir mais stock élevé). `nil` si
    /// pas assez de recul.
    let charge: NiveauChargeActive?

    let issue: IssueEndormissement

    /// `true` si un resucrage **correctif** de cette soirée a été suivi d'une
    /// **nouvelle** hypo dans l'heure : la correction n'a pas tenu. Même
    /// définition que B1 (`BilanHyposNuit.rechutes`), calculée par
    /// `DetectionRechute` pour que l'app n'ait qu'un seul sens du mot.
    var rechute: Bool = false
}

// MARK: - Snapshot B2

/// Snapshot prêt à afficher de l'analyse « Endormissement ».
/// `nuits` est triée par glycémie de coucher **croissante** : le risque se
/// concentre en haut, la lecture raconte l'histoire du plancher.
nonisolated struct AnalyseEndormissement: Sendable, Equatable {

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
