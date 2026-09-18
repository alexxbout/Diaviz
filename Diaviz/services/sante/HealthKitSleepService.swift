//
//  HealthKitSleepService.swift
//  diaviz
//

import Foundation
import HealthKit
import OSLog

/// Accès lecture aux stades de sommeil (`HKCategoryTypeIdentifier.sleepAnalysis`)
/// dans Apple Santé — même pattern d'auth/query que `HealthKitCGMService` et
/// `HealthKitImportService` : HealthKit ne fonctionne que sur device réel, on
/// demande l'autorisation puis on lit (liste vide = refus ou absence de donnée,
/// impossible à distinguer côté API).
///
/// Alimente uniquement l'overlay de `CourbesNocturnesChart` (vue « Par nuit »)
/// — aucune persistance, aucun calcul dérivé, aucun verdict : la donnée est
/// affichée telle quelle ou pas du tout (dégradation gracieuse stricte).
@MainActor
@Observable
final class HealthKitSleepService {

    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    private(set) var message: String?

    static var disponible: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Demande l'autorisation de lecture du sommeil.
    @discardableResult
    func demanderAcces() async -> Bool {
        guard Self.disponible else {
            message = "HealthKit indisponible sur cet appareil (essaie sur un iPhone réel)."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType])
            Logger.sante.info("Autorisation lecture sommeil demandée")
            return true
        } catch {
            message = "Autorisation impossible : \(error.localizedDescription)"
            Logger.sante.error("auth sommeil: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Lit les échantillons de sommeil chevauchant `plage` et les mappe en
    /// intervalles triés. Retourne `[]` sans distinction refus/absence — c'est
    /// au call site de décider comment se dégrader (jamais de bande vide/fausse).
    func stades(sur plage: ClosedRange<Date>) async -> [SleepStageInterval] {
        guard Self.disponible else { return [] }
        // Requête légèrement élargie de part et d'autre : un échantillon peut
        // démarrer avant la borne basse (endormissement avant le début de la
        // fenêtre nuit) — on le garde, il sera clampé au rendu par le chart
        // (chartXScale coupe visuellement ce qui dépasse le domaine).
        let debut = plage.lowerBound.addingTimeInterval(-3600)
        let fin = plage.upperBound.addingTimeInterval(3600)
        let predicat = HKQuery.predicateForSamples(withStart: debut, end: fin)
        let descripteur = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicat)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 500
        )
        do {
            let resultats = try await descripteur.result(for: store)
            message = nil
            let intervalles = resultats.compactMap(Self.intervalle(depuis:))
            Logger.sante.info("Lecture sommeil : \(intervalles.count, privacy: .public) intervalles")
            return intervalles
        } catch {
            message = "Lecture impossible : \(error.localizedDescription)"
            Logger.sante.error("query sommeil: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Mapping

    /// Convertit un échantillon HealthKit en intervalle. `inBed` est conservé
    /// (contexte « au lit ») mais l'overlay chart peut choisir de ne pas le
    /// dessiner — c'est un fait factuel distinct de « endormi ».
    private static func intervalle(depuis sample: HKCategorySample) -> SleepStageInterval? {
        guard let stage = stade(depuis: sample.value) else { return nil }
        return SleepStageInterval(stage: stage, debut: sample.startDate, fin: sample.endDate)
    }

    private static func stade(depuis valeur: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: valeur) {
        case .awake:              return .awake
        case .asleepREM:          return .rem
        case .asleepCore:         return .core
        case .asleepDeep:         return .deep
        case .asleepUnspecified:  return .asleepGenerique
        // Ancienne API / sources qui ne distinguent pas les stades fins —
        // fallback gracieux : on affiche « sommeil » générique plutôt que rien.
        case .inBed:              return .inBed
        default:                  return nil
        }
    }
}
