//
//  HealthKitWorkoutData.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import Foundation

/// Données HealthKit conservées sur une activité importée. Snapshot
/// figé au moment de l'import — la source de vérité reste Apple Santé,
/// mais on garde une copie locale pour pouvoir afficher FC/calories/
/// distance dans le détail sans re-requêter le store HealthKit à
/// chaque ouverture.
///
/// Tous les champs sont optionnels parce que selon le type d'activité
/// et l'appareil source (Apple Watch vs iPhone), certaines métriques
/// peuvent ne pas avoir été enregistrées (par ex. la distance pour
/// une séance de yoga, ou la FC sans bracelet).
struct HealthKitWorkoutData: Codable, Sendable, Hashable {
    /// Identifiant HKWorkout côté Apple Santé — utilisé à terme pour
    /// dédupliquer un éventuel re-import.
    let workoutUUID: UUID

    /// Fréquence cardiaque moyenne sur la session, en battements/min.
    let fcMoyenne: Double?

    /// Pic de fréquence cardiaque atteint sur la session.
    let fcMax: Double?

    /// Calories actives brûlées (énergie active, hors métabolisme de base),
    /// en kilocalories.
    let caloriesActives: Double?

    /// Distance parcourue, en mètres. `nil` pour les activités sans
    /// déplacement (musculation, yoga).
    let distanceMetres: Double?

    /// Libellé de l'appareil source — « Apple Watch Series 9 », « iPhone »,
    /// etc. Affiché dans le détail pour traçabilité.
    let sourceAppareil: String
}
