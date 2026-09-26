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

    /// `true` si la demande d'autorisation n'a plus rien à montrer (déjà
    /// tranchée) : les lectures peuvent démarrer sans attendre le préflight
    /// Santé du démarrage.
    func autorisationTranchee() async -> Bool {
        guard Self.disponible else { return false }
        let statut = try? await store.statusForAuthorizationRequest(
            toShare: [], read: [typePas, typeFC, HKObjectType.workoutType()]
        )
        return statut == .unnecessary
    }

    /// Premier pas utile pour borner l'historique. Seule compte la question
    /// « l'historique remonte-t-il avant `borne` ? » : si oui, **n'importe
    /// quel** échantillon antérieur suffit (requête sans tri, instantanée) —
    /// trier des années de pas pour trouver le tout premier coûtait cher.
    /// Sinon, plus ancien échantillon de la fenêtre. `nil` = aucun pas lisible.
    func premierPas(borne: Date) async -> Date? {
        guard Self.disponible else { return nil }
        let avant = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: typePas, predicate: HKQuery.predicateForSamples(withStart: nil, end: borne))],
            sortDescriptors: [],
            limit: 1
        )
        if let ancien = (try? await avant.result(for: store))?.first?.startDate { return ancien }
        let dansFenetre = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: typePas, predicate: HKQuery.predicateForSamples(withStart: borne, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 1
        )
        return (try? await dansFenetre.result(for: store))?.first?.startDate
    }

    /// Pas par bloc de 10 min sur `intervalle` — premier passage du préfiltrage.
    func pasParBloc(sur intervalle: DateInterval, calendrier: Calendar = .current) async -> [PasBloc] {
        let debut = calendrier.dateInterval(of: .hour, for: intervalle.start)?.start ?? intervalle.start
        return await sommes(de: debut, a: intervalle.end, pas: DateComponents(minute: CalculChargeActive.dureeBlocMinutes))
            .map { PasBloc(debut: $0.debut, pas: $0.pas) }
    }

    /// Pas par minute sur chaque plage candidate. HealthKit fusionne les
    /// sources (iPhone + montre) et répartit les échantillons au prorata des
    /// buckets : pas de double comptage. Au plus `parallelisme` requêtes à
    /// la fois : en lancer des centaines d'un coup les fait attendre les unes
    /// derrière les autres côté HealthKit.
    func pasParMinute(plages: [DateInterval], parallelisme: Int = 4) async -> [PasMinute] {
        await withTaskGroup(of: [PasMinute].self) { groupe in
            var restantes = plages[...]
            func lancer() {
                guard let plage = restantes.popFirst() else { return }
                groupe.addTask {
                    await sommes(de: plage.start, a: plage.end, pas: DateComponents(minute: 1))
                        .map { PasMinute(debut: $0.debut, pas: $0.pas) }
                }
            }
            for _ in 0..<parallelisme { lancer() }
            var minutes: [PasMinute] = []
            for await lot in groupe {
                minutes += lot
                lancer()
            }
            return minutes
        }
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
