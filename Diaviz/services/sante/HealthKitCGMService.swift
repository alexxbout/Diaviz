//
//  HealthKitCGMService.swift
//  diaviz
//
//  Created by Alexandre on 15/06/2026.
//

import Foundation
import HealthKit
import OSLog
import SwiftData

/// Échantillon de glycémie lu depuis Apple Santé (diagnostic). Snapshot léger
/// pour inspecter ce que Dexcom écrit réellement dans HealthKit.
nonisolated struct EchantillonCGM: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let valeur: Int
    let source: String
    let appareil: String?
    /// Valeur brute de la métadonnée Dexcom « Trend Arrow » (encodage à mapper).
    let trendArrow: String?
    /// Valeur brute de « Trend Rate » (mg/dL/min).
    let trendRate: String?
    let metadata: String?
}

/// Accès lecture aux glycémies dans Apple Santé. HealthKit ne fonctionne **que
/// sur device réel** (pas le simulateur). On ne peut pas connaître l'état exact
/// d'une autorisation de *lecture* (confidentialité) : on demande puis on lit ;
/// liste vide = soit refus, soit aucune donnée.
@MainActor
@Observable
final class HealthKitCGMService {
    private let store = HKHealthStore()
    private let glucose = HKQuantityType(.bloodGlucose)
    /// mg/dL = milligrammes par décilitre.
    private let mgParDL = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))

    private(set) var message: String?
    /// Dernière ingestion réussie (pour l'UI / debug).
    private(set) var derniereIngestion: Date?
    private(set) var nombreIngere: Int?

    /// Clé UserDefaults de l'ancre de requête incrémentale.
    private let cleAnchor = "healthkit.glucose.anchor"
    /// Fenêtre du premier pull : 7 jours (assez pour le score journalier sur une
    /// semaine ; pas de backfill profond, les analyses event-based démarrent à vide).
    private let fenetreInitiale: TimeInterval = 7 * 24 * 3600

    static var disponible: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Demande l'autorisation de lecture de la glycémie.
    @discardableResult
    func demanderAcces() async -> Bool {
        guard Self.disponible else {
            message = "HealthKit indisponible sur cet appareil (essaie sur un iPhone réel)."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [glucose])
            Logger.sante.info("Autorisation lecture glycémie demandée")
            return true
        } catch {
            message = "Autorisation impossible : \(error.localizedDescription)"
            Logger.sante.error("auth: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Lit les échantillons de glycémie des dernières `heures`, du plus récent
    /// au plus ancien.
    func echantillonsRecents(heures: Int = 24) async -> [EchantillonCGM] {
        let depuis = Date.now.addingTimeInterval(-Double(heures) * 3600)
        let predicat = HKQuery.predicateForSamples(withStart: depuis, end: nil)
        let descripteur = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: glucose, predicate: predicat)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 500
        )
        do {
            let resultats = try await descripteur.result(for: store)
            message = nil
            Logger.sante.info("Lecture glycémie : \(resultats.count, privacy: .public) échantillons")
            return resultats.map { echantillon in
                let meta = echantillon.metadata
                return EchantillonCGM(
                    date: echantillon.startDate,
                    valeur: Int(echantillon.quantity.doubleValue(for: mgParDL).rounded()),
                    source: echantillon.sourceRevision.source.name,
                    appareil: echantillon.device?.name,
                    trendArrow: meta?["Trend Arrow"].map { "\($0)" },
                    trendRate: meta?["Trend Rate"].map { "\($0)" },
                    metadata: meta?.keys.sorted().joined(separator: ", ")
                )
            }
        } catch {
            message = "Lecture impossible : \(error.localizedDescription)"
            Logger.sante.error("query: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Ingestion dans le hub

    /// Récupère les **nouveaux** échantillons depuis la dernière ancre et les
    /// ingère dans le hub `GlucoseReading`. Premier appel (ancre absente) borné à
    /// `fenetreInitiale`. Idempotent (dédup sur l'horodatage). Renvoie le nombre ajouté.
    @discardableResult
    func synchroniser(container: ModelContainer) async -> Int {
        guard Self.disponible else { return 0 }
        let ancre = chargerAncre()
        let predicat: NSPredicate? = ancre == nil
            ? HKQuery.predicateForSamples(withStart: Date.now.addingTimeInterval(-fenetreInitiale), end: nil)
            : nil
        let descripteur = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: glucose, predicate: predicat)],
            anchor: ancre
        )
        do {
            let resultat = try await descripteur.result(for: store)
            sauvegarderAncre(resultat.newAnchor)
            let ajoutes = ingerer(resultat.addedSamples, dans: container.mainContext)
            derniereIngestion = .now
            nombreIngere = ajoutes
            Logger.sante.info("Ingestion HealthKit : \(ajoutes, privacy: .public) ajoutées / \(resultat.addedSamples.count, privacy: .public) reçues")
            return ajoutes
        } catch {
            Logger.sante.error("sync: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Oublie l'ancre incrémentale et relance une ingestion complète sur
    /// `fenetreInitiale`.
    ///
    /// L'ancre vit en `UserDefaults`, le hub en SwiftData : si le store est
    /// recréé (migration de schéma) alors que l'ancre survit, `synchroniser`
    /// ne demande plus que les nouveautés et le hub reste vide indéfiniment.
    /// C'est la porte de sortie de cette situation.
    @discardableResult
    func resynchroniserToutDepuisSante(container: ModelContainer) async -> Int {
        UserDefaults.standard.removeObject(forKey: cleAnchor)
        Logger.sante.info("Ancre HealthKit réinitialisée — réimport complet demandé")
        return await synchroniser(container: container)
    }

    /// Observe les nouvelles glycémies (réveil en arrière-plan inclus) et
    /// déclenche une synchro à chaque arrivée.
    func demarrerSurveillance(container: ModelContainer) {
        // `@Sendable` explicite : HealthKit appelle ces rappels sur sa propre
        // file. En mode Swift 6, une fermeture héritant du `MainActor` y
        // arrêterait l'app, sans que le compilateur le signale.
        let observateur = HKObserverQuery(sampleType: glucose, predicate: nil) { @Sendable [weak self] _, completion, erreur in
            if let erreur {
                Logger.sante.error("observer: \(erreur.localizedDescription, privacy: .public)")
                completion()
                return
            }
            // HealthKit documente ce rappel comme appelable depuis n'importe
            // quel thread ; son type ne le dit simplement pas.
            nonisolated(unsafe) let terminer = completion
            Task { @MainActor in
                await self?.synchroniser(container: container)
                terminer()
            }
        }
        store.execute(observateur)
        store.enableBackgroundDelivery(for: glucose, frequency: .hourly) { @Sendable ok, erreur in
            if let erreur {
                Logger.sante.error("background delivery: \(erreur.localizedDescription, privacy: .public)")
            } else {
                Logger.sante.info("background delivery activé : \(ok, privacy: .public)")
            }
        }
    }

    private func ingerer(_ samples: [HKQuantitySample], dans context: ModelContext) -> Int {
        guard !samples.isEmpty else { return 0 }
        let dejaPresentes = datesExistantes(samples.map(\.startDate), dans: context)
        var ajoutes = 0
        for sample in samples where !dejaPresentes.contains(sample.startDate) {
            let valeur = Int(sample.quantity.doubleValue(for: mgParDL).rounded())
            let arrow = sample.metadata?["Trend Arrow"].map { "\($0)" }
            let rate = (sample.metadata?["Trend Rate"] as? NSNumber)?.doubleValue
            context.insert(
                GlucoseReading(
                    date: sample.startDate,
                    valeur: valeur,
                    tendance: TendanceGlycemie(healthKitTrendArrow: arrow),
                    tauxVariation: rate,
                    source: .healthkit
                )
            )
            ajoutes += 1
        }
        if ajoutes > 0 { try? context.save() }
        return ajoutes
    }

    private func datesExistantes(_ dates: [Date], dans context: ModelContext) -> Set<Date> {
        guard let borneMin = dates.min(), let borneMax = dates.max() else { return [] }
        let descripteur = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= borneMin && $0.date <= borneMax }
        )
        return Set((try? context.fetch(descripteur))?.map(\.date) ?? [])
    }

    private func chargerAncre() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: cleAnchor) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func sauvegarderAncre(_ ancre: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: ancre, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: cleAnchor)
    }
}
