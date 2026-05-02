//
//  HealthKitImportService.swift
//  insulog
//
//  Created by Alexandre on 02/05/2026.
//

import Foundation
import Observation

/// Service centralisé qui orchestre l'import d'activités sportives
/// depuis Apple Santé (HealthKit) — version **mockée** pour développer
/// l'expérience UI sans framework HealthKit ni autorisation utilisateur.
///
/// Trois ensembles disjoints d'identifiants :
/// - **`workoutsEnAttente`** : à proposer à l'utilisateur (badges +
///   sheet d'import).
/// - **`workoutsImportes`** : déjà créés en `ActiviteSportive` côté
///   InsuLog, ne seront plus reproposés.
/// - **`workoutsIgnores`** : explicitement écartés par l'utilisateur,
///   ne seront plus reproposés non plus.
///
/// Dans la version réelle, `workoutsEnAttente` sera alimenté par une
/// requête `HKSampleQuery` filtrée sur la période depuis le dernier
/// import, en excluant les UUIDs déjà présents dans les deux autres
/// ensembles. Ici on charge un mock fixe au boot pour exercer l'UX.
///
/// Annoté `@MainActor` parce que la totalité des accès se font depuis
/// la couche SwiftUI (badges, sheet) — pas la peine d'introduire un
/// actor dédié pour un service qui ne fait qu'agréger de l'état UI.
@Observable
@MainActor
final class HealthKitImportService {

    /// Singleton accessible depuis n'importe quelle vue. À terme on
    /// l'injectera via `@Environment` ; pour l'instant l'usage en
    /// `@State` direct dans les vues racines suffit.
    static let shared = HealthKitImportService()

    // MARK: - État observable

    private(set) var workoutsEnAttente: [WorkoutHealthKitMock] = []

    /// Sets privés — pas observables, mais `@Observable` n'a pas besoin
    /// de tracker leur lecture (rien dans l'UI ne les consomme).
    private var workoutsIgnores: Set<UUID> = []
    private var workoutsImportes: Set<UUID> = []

    // MARK: - API publique de lecture

    var nombreEnAttente: Int { workoutsEnAttente.count }
    var aDesImportsEnAttente: Bool { nombreEnAttente > 0 }

    // MARK: - Init

    private init() {
        chargerMockInitial()
    }

    /// Init alternatif pour les previews — n'utilise pas le mock par
    /// défaut, ce qui permet d'instancier un service vide ou avec une
    /// liste précise. Le label du paramètre sert d'unique discriminateur
    /// avec l'init principal sans avoir à introduire un enum de mode.
    private init(skipDefaultMock _: Bool) {}

    /// Au démarrage, simule la détection de deux activités par l'Apple
    /// Watch depuis le dernier lancement. Volontairement court — on ne
    /// veut pas surcharger le premier écran.
    private func chargerMockInitial() {
        workoutsEnAttente = [.mockCourse, .mockYoga]
    }

    // MARK: - Actions

    /// Marque un workout comme ignoré : il ne sera plus jamais proposé,
    /// même si HealthKit le re-renvoie. Pas de confirmation — l'action
    /// est réversible côté Apple Santé (l'utilisateur peut toujours
    /// retrouver l'activité dans l'app Santé d'Apple).
    func ignorer(_ workout: WorkoutHealthKitMock) {
        workoutsIgnores.insert(workout.id)
        workoutsEnAttente.removeAll { $0.id == workout.id }
    }

    /// Importe un workout dans le journal InsuLog : crée une nouvelle
    /// `ActiviteSportive` côté `ActivitesSportServiceMock`, marque le
    /// workout comme importé, et le retire de la file d'attente.
    ///
    /// `glucidesPreSport` et `intensite` viennent de l'enrichissement
    /// utilisateur dans la sheet — on ne devine pas l'intensité depuis
    /// la FC ici (c'est le rôle de la vue, pour pouvoir la pré-remplir
    /// puis laisser l'utilisateur ajuster).
    func importer(
        _ workout: WorkoutHealthKitMock,
        glucidesPreSport: Double?,
        intensite: IntensiteSport
    ) {
        let donneesHK = HealthKitWorkoutData(
            workoutUUID: workout.id,
            fcMoyenne: workout.fcMoyenne,
            fcMax: workout.fcMax,
            caloriesActives: workout.caloriesActives,
            distanceMetres: workout.distanceMetres,
            sourceAppareil: workout.sourceAppareil
        )

        let activite = ActiviteSportive(
            type: workout.typeSport,
            dateDebut: workout.dateDebut,
            dureeMinutes: workout.dureeMinutes,
            intensite: intensite,
            glucidesPreSport: glucidesPreSport,
            note: nil,
            source: .healthKit,
            healthKitData: donneesHK
        )

        ActivitesSportServiceMock.shared.ajouter(activite)

        workoutsImportes.insert(workout.id)
        workoutsEnAttente.removeAll { $0.id == workout.id }
    }

    // MARK: - Fabriques pour previews
    //
    // `init` étant privé, on expose deux fabriques nommées qui
    // construisent un service indépendant du singleton — utile pour
    // exercer la sheet et les vues badge dans plusieurs états.

    static func mockAvecActivites(_ activites: [WorkoutHealthKitMock]) -> HealthKitImportService {
        let service = HealthKitImportService(skipDefaultMock: true)
        service.workoutsEnAttente = activites
        return service
    }

    static func mockVide() -> HealthKitImportService {
        HealthKitImportService(skipDefaultMock: true)
    }
}

// MARK: - Helper d'inférence d'intensité

/// Dérive l'intensité ressentie depuis la fréquence cardiaque moyenne
/// du workout. Heuristique simple basée sur le pourcentage de la FC
/// max théorique (190 — à terme depuis le profil utilisateur, paramétré
/// dans les réglages).
///
/// Seuils calibrés sur les zones d'effort classiques :
/// - **< 60 % FCmax** → faible (récupération)
/// - **60–80 %**       → modérée (zone aérobie)
/// - **> 80 %**        → intense (zone anaérobie)
///
/// Retourne `.moderee` quand la FC n'est pas disponible — c'est la
/// valeur médiane, la moins perturbante par rapport à un cas inconnu.
func intensiteDepuisFC(_ fcMoyenne: Double?) -> IntensiteSport {
    guard let fc = fcMoyenne else { return .moderee }
    let pourcentage = fc / 190
    if pourcentage < 0.6 { return .faible }
    if pourcentage < 0.8 { return .moderee }
    return .intense
}
