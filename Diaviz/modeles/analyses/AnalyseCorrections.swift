//
//  AnalyseCorrections.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import Foundation

// MARK: - Issue d'une correction du soir

/// Résultat **factuel** d'une correction prise au coucher, classé selon où la
/// glycémie a atterri par rapport à la cible. Observation rétrospective, jamais
/// une recommandation de dose.
enum IssueCorrection: Sendable, Equatable {

    /// La glycémie est restée au-dessus de la cible (correction trop faible).
    case insuffisant

    /// La glycémie est revenue en cible.
    case adapte

    /// La glycémie est descendue sous la cible / hypo (correction trop forte).
    case surCorrection
}

// MARK: - Une correction du soir

/// Une correction d'insuline rapide prise au coucher, avec son contexte et son
/// issue. B3 est **event-based** : déclenché par la présence d'une correction,
/// sans seuil de glycémie.
struct CorrectionSoir: Identifiable, Sendable, Equatable {

    let id: UUID
    let date: Date

    /// Glycémie (mg/dL) au moment de la correction.
    let glycemie: Int

    /// Tendance de la glycémie au moment de la correction (trajectoire).
    let tendance: TendanceGlycemie

    /// Glucides ingérés autour de la correction (g). `nil` si aucun.
    let glucides: Double?

    /// Dose de correction (unités de rapide).
    let dose: Double

    /// IOB résiduel au moment de la correction (unités). `nil` si nul.
    /// Facteur clé : corriger par-dessus de l'IOB → risque de sur-correction.
    let iob: Double?

    /// Séance de sport le jour même (détail au tap). `nil` si aucune.
    let sport: SportResume?

    /// Charge d'activité de la semaine (contexte transverse).
    let charge: ChargeActivite

    let issue: IssueCorrection
}

// MARK: - Snapshot B3

/// Snapshot prêt à afficher de l'analyse « Corrections du soir ».
/// `corrections` triée par glycémie croissante (l'axe de comparaison premier).
struct AnalyseCorrections: Sendable, Equatable {

    let corrections: [CorrectionSoir]

    var nombre: Int { corrections.count }
}
