//
//  WorkoutHealthKitMock.swift
//  insulog
//
//  Created by Alexandre on 02/05/2026.
//

import Foundation

/// Représentation **mockée** d'un workout Apple Santé en attente
/// d'import dans InsuLog. Calque la structure d'un `HKWorkout` réel
/// (à terme remplacée par une conversion depuis HealthKit), mais reste
/// indépendante du framework — on doit pouvoir tester l'expérience
/// d'import en preview sans toucher au store HealthKit.
///
/// Distinct de `HealthKitWorkoutData` : ce dernier est conservé sur
/// l'`ActiviteSportive` après import (snapshot final), tandis que
/// `WorkoutHealthKitMock` représente un workout brut **avant** import,
/// avec en plus le `typeSport` déjà mappé sur notre taxonomie interne.
struct WorkoutHealthKitMock: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let typeSport: TypeSport
    let dateDebut: Date
    let dureeMinutes: Int
    let fcMoyenne: Double?
    let fcMax: Double?
    let caloriesActives: Double?
    let distanceMetres: Double?
    let sourceAppareil: String
}

// MARK: - Mocks pré-définis

extension WorkoutHealthKitMock {

    /// Date du jour à `h:m`, indépendante du fuseau et calée sur le
    /// calendrier courant — utile pour rendre les previews cohérentes
    /// avec « ce matin / ce midi » indépendamment de l'heure d'exécution.
    private static func aujourdHui(_ h: Int, _ m: Int = 0) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    /// Course matinale type — Apple Watch, FC élevée, distance ~7km.
    static let mockCourse = WorkoutHealthKitMock(
        id: UUID(),
        typeSport: .course,
        dateDebut: aujourdHui(7, 15),
        dureeMinutes: 45,
        fcMoyenne: 145,
        fcMax: 168,
        caloriesActives: 420,
        distanceMetres: 7200,
        sourceAppareil: "Apple Watch Series 9"
    )

    /// Yoga doux du midi — FC basse, pas de distance.
    static let mockYoga = WorkoutHealthKitMock(
        id: UUID(),
        typeSport: .yoga,
        dateDebut: aujourdHui(12, 0),
        dureeMinutes: 30,
        fcMoyenne: 95,
        fcMax: 112,
        caloriesActives: 110,
        distanceMetres: nil,
        sourceAppareil: "Apple Watch Series 9"
    )

    /// Séance de musculation — FC modérée mais pic élevé sur les séries
    /// lourdes, pas de distance.
    static let mockMusculation = WorkoutHealthKitMock(
        id: UUID(),
        typeSport: .musculation,
        dateDebut: aujourdHui(18, 30),
        dureeMinutes: 50,
        fcMoyenne: 118,
        fcMax: 152,
        caloriesActives: 280,
        distanceMetres: nil,
        sourceAppareil: "Apple Watch Series 9"
    )

    /// Sortie vélo — FC modérée prolongée, distance importante.
    static let mockVelo = WorkoutHealthKitMock(
        id: UUID(),
        typeSport: .velo,
        dateDebut: aujourdHui(17, 30),
        dureeMinutes: 60,
        fcMoyenne: 132,
        fcMax: 158,
        caloriesActives: 510,
        distanceMetres: 22000,
        sourceAppareil: "Apple Watch Series 9"
    )
}
