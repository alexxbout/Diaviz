//
//  HealthKitImportService.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import Foundation
import HealthKit
import Observation
import OSLog

/// Service centralisé qui orchestre l'import d'activités sportives
/// depuis Apple Santé (HealthKit).
///
/// Trois ensembles disjoints d'identifiants (clés = `HKWorkout.uuid`) :
/// - **`workoutsEnAttente`** : à proposer à l'utilisateur (badges +
///   sheet d'import).
/// - **`workoutsImportes`** : déjà créés en `ActiviteSportive` côté
///   Diaviz, ne seront plus reproposés. Persisté en UserDefaults pour
///   survivre au relaunch (le hub SwiftData ne référence pas l'UUID
///   HealthKit de façon interrogeable rapidement).
/// - **`workoutsIgnores`** : explicitement écartés par l'utilisateur,
///   ne seront plus reproposés non plus. Même persistance.
///
/// HealthKit ne fonctionne **que sur device réel** (pas le simulateur) —
/// sur simulateur/previews on retombe sur un mock fixe pour garder l'UX
/// testable sans dépendre du framework.
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

    static var disponible: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Fenêtre de recherche des workouts récents — cohérente avec la
    /// fenêtre 7 j des analyses coucher.
    private let fenetreRecherche: TimeInterval = 7 * 24 * 3600

    private let cleWorkoutsImportes = "healthkit.sport.importes"
    private let cleWorkoutsIgnores = "healthkit.sport.ignores"

    private let store = HKHealthStore()
    private let workoutType = HKObjectType.workoutType()

    // MARK: - État observable

    private(set) var workoutsEnAttente: [WorkoutHealthKitCandidat] = []
    private(set) var message: String?

    /// Sets privés — pas observables, mais `@Observable` n'a pas besoin
    /// de tracker leur lecture (rien dans l'UI ne les consomme).
    private var workoutsIgnores: Set<UUID>
    private var workoutsImportes: Set<UUID>

    // MARK: - API publique de lecture

    var nombreEnAttente: Int { workoutsEnAttente.count }
    var aDesImportsEnAttente: Bool { nombreEnAttente > 0 }

    // MARK: - Init

    private init() {
        workoutsImportes = Self.chargerUUIDs(cle: cleWorkoutsImportes)
        workoutsIgnores = Self.chargerUUIDs(cle: cleWorkoutsIgnores)
        guard Self.disponible else {
            chargerMockInitial()
            return
        }
    }

    /// Init alternatif pour les previews — n'utilise pas le mock par
    /// défaut, ce qui permet d'instancier un service vide ou avec une
    /// liste précise. Le label du paramètre sert d'unique discriminateur
    /// avec l'init principal sans avoir à introduire un enum de mode.
    private init(skipDefaultMock _: Bool) {
        workoutsImportes = []
        workoutsIgnores = []
    }

    /// Fallback simulateur/preview : deux activités fixes pour exercer
    /// l'UX sans dépendre du framework HealthKit (indisponible hors
    /// device réel).
    private func chargerMockInitial() {
        workoutsEnAttente = [.mockCourse, .mockYoga]
    }

    // MARK: - Autorisation & synchronisation

    /// Demande l'autorisation de lecture des séances sportives.
    @discardableResult
    func demanderAcces() async -> Bool {
        guard Self.disponible else {
            message = "HealthKit indisponible sur cet appareil (essaie sur un iPhone réel)."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [workoutType])
            Logger.sante.info("Autorisation lecture séances sportives demandée")
            return true
        } catch {
            message = "Autorisation impossible : \(error.localizedDescription)"
            Logger.sante.error("auth sport: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Recharge `workoutsEnAttente` depuis HealthKit : workouts des
    /// `fenetreRecherche` derniers jours, en excluant ceux déjà importés
    /// ou ignorés.
    func rafraichir() async {
        guard Self.disponible else { return }
        let depuis = Date.now.addingTimeInterval(-fenetreRecherche)
        let predicat = HKQuery.predicateForSamples(withStart: depuis, end: nil)
        let descripteur = HKSampleQueryDescriptor(
            predicates: [.workout(predicat)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 50
        )
        do {
            let workouts = try await descripteur.result(for: store)
            message = nil
            workoutsEnAttente = workouts
                .filter { !workoutsImportes.contains($0.uuid) && !workoutsIgnores.contains($0.uuid) }
                .map(Self.candidat(depuis:))
            Logger.sante.info("Séances en attente : \(self.workoutsEnAttente.count, privacy: .public)")
        } catch {
            message = "Lecture impossible : \(error.localizedDescription)"
            Logger.sante.error("query sport: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Actions

    /// Marque un workout comme ignoré : il ne sera plus jamais proposé,
    /// même si HealthKit le re-renvoie. Pas de confirmation — l'action
    /// est réversible côté Apple Santé (l'utilisateur peut toujours
    /// retrouver l'activité dans l'app Santé d'Apple).
    func ignorer(_ workout: WorkoutHealthKitCandidat) {
        workoutsIgnores.insert(workout.id)
        Self.sauvegarderUUIDs(workoutsIgnores, cle: cleWorkoutsIgnores)
        workoutsEnAttente.removeAll { $0.id == workout.id }
    }

    /// Construit l'`ActiviteSportive` (source `.healthKit`) correspondant à
    /// un workout, marque le workout comme importé et le retire de la file
    /// d'attente, puis **retourne** l'activité.
    ///
    /// La persistance dans le hub n'est PAS faite ici : ce service ne connaît
    /// pas le `ModelContext`. C'est la vue appelante qui passe l'activité
    /// retournée à `ActivitesSportService.enregistrer(_:)` — un seul service
    /// écrit dans le hub, ce service-ci ne fait qu'orchestrer la détection.
    ///
    /// `glucidesPreSport` et `intensite` viennent de l'enrichissement
    /// utilisateur dans la sheet — on ne devine pas l'intensité depuis
    /// la FC ici (c'est le rôle de la vue, pour pouvoir la pré-remplir
    /// puis laisser l'utilisateur ajuster).
    @discardableResult
    func importer(
        _ workout: WorkoutHealthKitCandidat,
        glucidesPreSport: Double?,
        intensite: IntensiteSport
    ) -> ActiviteSportive {
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
            alimentsPreSport: glucidesPreSport.map { [.collationGenerique(glucidesGrammes: $0)] } ?? [],
            note: nil,
            source: .healthKit,
            healthKitData: donneesHK
        )

        workoutsImportes.insert(workout.id)
        Self.sauvegarderUUIDs(workoutsImportes, cle: cleWorkoutsImportes)
        workoutsEnAttente.removeAll { $0.id == workout.id }

        return activite
    }

    // MARK: - Mapping HKWorkout → WorkoutHealthKitCandidat

    private static func candidat(depuis workout: HKWorkout) -> WorkoutHealthKitCandidat {
        WorkoutHealthKitCandidat(
            id: workout.uuid,
            typeSport: typeSport(depuis: workout.workoutActivityType),
            dateDebut: workout.startDate,
            dureeMinutes: Int(workout.duration / 60),
            fcMoyenne: valeur(workout, .heartRate, unite: HKUnit.count().unitDivided(by: .minute())) { $0.averageQuantity() },
            fcMax: valeur(workout, .heartRate, unite: HKUnit.count().unitDivided(by: .minute())) { $0.maximumQuantity() },
            caloriesActives: valeur(workout, .activeEnergyBurned, unite: .kilocalorie()) { $0.sumQuantity() },
            distanceMetres: distanceMetres(pour: workout),
            sourceAppareil: workout.sourceRevision.source.name
        )
    }

    /// Lit une statistique attachée au workout pour un type de quantité
    /// donné — disponible directement sur `HKWorkout` depuis iOS 16 (plus
    /// besoin d'une requête séparée sur les échantillons bruts).
    private static func valeur(
        _ workout: HKWorkout,
        _ identifiant: HKQuantityTypeIdentifier,
        unite: HKUnit,
        extraire: (HKStatistics) -> HKQuantity?
    ) -> Double? {
        guard let stats = workout.statistics(for: HKQuantityType(identifiant)) else { return nil }
        return extraire(stats)?.doubleValue(for: unite)
    }

    /// Distance parcourue — le type de quantité varie selon l'activité
    /// (course/marche, vélo, natation) ; on essaie les types plausibles
    /// dans l'ordre et prend le premier renseigné.
    private static func distanceMetres(pour workout: HKWorkout) -> Double? {
        let types: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning, .distanceCycling, .distanceSwimming
        ]
        for type in types {
            if let sum = valeur(workout, type, unite: .meter(), extraire: { $0.sumQuantity() }) {
                return sum
            }
        }
        return nil
    }

    private static func typeSport(depuis activite: HKWorkoutActivityType) -> TypeSport {
        switch activite {
        case .running:
            return .course
        case .cycling:
            return .velo
        case .swimming:
            return .natation
        case .walking, .hiking:
            return .marche
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining:
            return .musculation
        case .yoga, .mindAndBody:
            return .yoga
        case .soccer, .basketball, .americanFootball, .baseball, .hockey, .tennis, .volleyball, .rugby:
            return .sportCollectif
        default:
            return .autre
        }
    }

    // MARK: - Persistance UserDefaults

    private static func chargerUUIDs(cle: String) -> Set<UUID> {
        let bruts = UserDefaults.standard.stringArray(forKey: cle) ?? []
        return Set(bruts.compactMap(UUID.init))
    }

    private static func sauvegarderUUIDs(_ ids: Set<UUID>, cle: String) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: cle)
    }

    // MARK: - Fabriques pour previews
    //
    // `init` étant privé, on expose deux fabriques nommées qui
    // construisent un service indépendant du singleton — utile pour
    // exercer la sheet et les vues badge dans plusieurs états.

    static func mockAvecActivites(_ activites: [WorkoutHealthKitCandidat]) -> HealthKitImportService {
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
/// max retenue (`CalculFCMax` : observée sur les séances, 190 en repli) —
/// la même que celle de la charge active.
///
/// Seuils calibrés sur les zones d'effort classiques :
/// - **< 60 % FCmax** → faible (récupération)
/// - **60–80 %**       → modérée (zone aérobie)
/// - **> 80 %**        → intense (zone anaérobie)
///
/// Retourne `.moderee` quand la FC n'est pas disponible — c'est la
/// valeur médiane, la moins perturbante par rapport à un cas inconnu.
func intensiteDepuisFC(_ fcMoyenne: Double?, fcMax: FCMaxRetenue) -> IntensiteSport {
    guard let fc = fcMoyenne, fcMax.bpm > 0 else { return .moderee }
    let pourcentage = fc / fcMax.bpm
    if pourcentage < 0.6 { return .faible }
    if pourcentage < 0.8 { return .moderee }
    return .intense
}
