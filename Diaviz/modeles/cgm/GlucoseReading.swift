//
//  GlucoseReading.swift
//  diaviz
//
//  Created by Alexandre on 14/06/2026.
//

import Foundation
import SwiftData

/// Mesure CGM brute du hub d'événements. **Fait horodaté absolu** : `date` porte
/// le `systemTime` UTC de Dexcom (source de vérité, clé de tri et de découpage des
/// nuits/journées). Le temps relatif est recalculé à l'affichage, jamais stocké.
///
/// Remplace le mock `PointCgm` (relatif). Toutes les vues dérivées (NightChartData,
/// TIR/GRI, tendances) se calculent à la volée depuis des tranches de cette entité.
///
/// `date` est la clé naturelle de déduplication, appliquée **côté app**
/// (`HealthKitCGMService.datesExistantes`, fetch + filtre avant insert) —
/// pas une contrainte `.unique` du store : CloudKit ne les supporte pas.
///
/// Pas de valeur par défaut réellement utilisée en pratique ci-dessous :
/// l'`init` garde tous ses paramètres obligatoires. C'est un filet de
/// secours exigé par le schéma CloudKit (récupération partielle de sync),
/// jamais exercé par le flux normal de l'app — cf. `ActiviteSportive.pauses`
/// pour le précédent qui a motivé cette règle.
@Model
nonisolated final class GlucoseReading {
    /// Horodatage absolu (= `systemTime` UTC pour la source `.dexcom`).
    var date: Date = Date.distantPast

    /// Glycémie en mg/dL.
    var valeur: Int = 0

    /// Trajectoire au moment de la mesure (flèche Dexcom), si fournie.
    var tendance: TendanceGlycemie?

    /// Taux de variation en mg/dL/min, fourni par Dexcom si disponible.
    var tauxVariation: Double?

    /// Provenance de la mesure.
    var source: SourceDonnee = SourceDonnee.manuel

    init(
        date: Date,
        valeur: Int,
        tendance: TendanceGlycemie? = nil,
        tauxVariation: Double? = nil,
        source: SourceDonnee
    ) {
        self.date = date
        self.valeur = valeur
        self.tendance = tendance
        self.tauxVariation = tauxVariation
        self.source = source
    }
}
