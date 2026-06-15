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
/// `date` est `unique` : c'est la clé naturelle de déduplication. Ré-ingérer la
/// même plage écrase au lieu de doublonner (idempotence au niveau du store).
@Model
final class GlucoseReading {
    /// Horodatage absolu (= `systemTime` UTC pour la source `.dexcom`).
    /// Clé naturelle : unique pour garantir l'ingestion idempotente.
    @Attribute(.unique) var date: Date

    /// Glycémie en mg/dL.
    var valeur: Int

    /// Trajectoire au moment de la mesure (flèche Dexcom), si fournie.
    var tendance: TendanceGlycemie?

    /// Taux de variation en mg/dL/min, fourni par Dexcom si disponible.
    var tauxVariation: Double?

    /// Provenance de la mesure.
    var source: SourceDonnee

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
