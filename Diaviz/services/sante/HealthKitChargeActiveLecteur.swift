//
//  HealthKitChargeActiveLecteur.swift
//  diaviz
//

import Foundation
import HealthKit
import OSLog

/// Workout Apple Santé réduit à ce qui compte pour la charge active :
/// fenêtre (dédoublonnage des bouts de marche), type et FC moyenne (jointure
/// avec les `ActiviteSportive` importées via `workoutUUID`).
nonisolated struct WorkoutPourCharge: Sendable {
    let uuid: UUID
    let intervalle: DateInterval
    /// `HKWorkoutActivityType.rawValue`.
    let typeActiviteHK: UInt
    let fcMoyenne: Double?
}

/// Lectures HealthKit de la charge active — pas (`stepCount`), workouts et
/// leur FC moyenne. Aucune persistance, aucun calcul : fournit les faits bruts
/// à `CalculChargeActive`. Même règle que les autres lecteurs Santé : un
/// résultat vide ne distingue pas un refus d'autorisation d'une absence de
/// donnée (l'API ne le permet pas en lecture).
nonisolated struct HealthKitChargeActiveLecteur: Sendable {

    private let store = HKHealthStore()
    private let typePas = HKQuantityType(.stepCount)
    private let typeFC = HKQuantityType(.heartRate)

    static var disponible: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Pas + FC + workouts. No-op silencieux si déjà tranché (accordé ou
    /// refusé) — normalement fait au préflight de démarrage (`AppTabVues`).
    func demanderAcces() async {
        guard Self.disponible else { return }
        do {
            try await store.requestAuthorization(
                toShare: [], read: [typePas, typeFC, HKObjectType.workoutType()]
            )
        } catch {
            Logger.sante.error("auth charge active: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Date du plus ancien échantillon de pas — borne la profondeur réelle de
    /// l'historique. `nil` = aucun pas lisible (refus ou absence).
    func premierPas() async -> Date? {
        guard Self.disponible else { return nil }
        let descripteur = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: typePas)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 1
        )
        return (try? await descripteur.result(for: store))?.first?.startDate
    }

    /// Pas par heure calendaire sur `intervalle` — premier passage, léger.
    func pasParHeure(sur intervalle: DateInterval, calendrier: Calendar = .current) async -> [PasHeure] {
        let debut = calendrier.dateInterval(of: .hour, for: intervalle.start)?.start ?? intervalle.start
        return await sommes(de: debut, a: intervalle.end, pas: DateComponents(hour: 1))
            .map { PasHeure(debut: $0.debut, pas: $0.pas) }
    }

    /// Pas par minute sur chaque plage candidate. HealthKit fusionne les
    /// sources (iPhone + montre) et répartit les échantillons au prorata des
    /// buckets : pas de double comptage.
    func pasParMinute(plages: [DateInterval]) async -> [PasMinute] {
        var minutes: [PasMinute] = []
        for plage in plages {
            minutes += await sommes(de: plage.start, a: plage.end, pas: DateComponents(minute: 1))
                .map { PasMinute(debut: $0.debut, pas: $0.pas) }
        }
        return minutes
    }

    /// Tous les workouts Apple Santé de `intervalle`, importés ou non dans le
    /// hub : un workout ignoré à l'import reste une séance réelle, ses pas ne
    /// doivent pas réapparaître comme marche.
    func workouts(sur intervalle: DateInterval) async -> [WorkoutPourCharge] {
        guard Self.disponible else { return [] }
        let predicat = HKQuery.predicateForSamples(withStart: intervalle.start, end: intervalle.end)
        let descripteur = HKSampleQueryDescriptor(
            predicates: [.workout(predicat)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 2000
        )
        guard let resultats = try? await descripteur.result(for: store) else { return [] }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return resultats.map { workout in
            WorkoutPourCharge(
                uuid: workout.uuid,
                intervalle: DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate)),
                typeActiviteHK: workout.workoutActivityType.rawValue,
                fcMoyenne: workout.statistics(for: typeFC)?.averageQuantity()?.doubleValue(for: bpm)
            )
        }
    }

    // MARK: - Statistiques

    private func sommes(de debut: Date, a fin: Date, pas: DateComponents) async -> [(debut: Date, pas: Double)] {
        guard Self.disponible, debut < fin else { return [] }
        let descripteur = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: typePas,
                predicate: HKQuery.predicateForSamples(withStart: debut, end: fin)
            ),
            options: .cumulativeSum,
            anchorDate: debut,
            intervalComponents: pas
        )
        do {
            let collection = try await descripteur.result(for: store)
            return collection.statistics().compactMap { stats in
                guard let somme = stats.sumQuantity()?.doubleValue(for: .count()), somme > 0 else { return nil }
                return (debut: stats.startDate, pas: somme)
            }
        } catch {
            Logger.sante.error("query pas: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
