//
//  CorrelationChargeTIRService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service **réel** de la page « Charge et équilibre glycémique » — lit le
/// contexte partagé de charge active (`ChargeActiveService`, à calculer
/// avant), `GlucoseReading` et les injections de lente sur la
/// fenêtre de `CalculCorrelationChargeTIR.nombreSemaines`, délègue à
/// `CalculCorrelationChargeTIR` (pur). Pattern aligné sur les autres
/// services hub : `synthese` démarre `nil`, peuplé à `demarrer`.
///
/// Pour la dérive basale par tranche (bloc 3), ce service fait tourner
/// `CalculAnalyseBasale` **une deuxième fois**, séparément du service B1
/// partagé de l'app (`AnalyseBasaleService`, fenêtre fixe 14 nuits) : ici la
/// fenêtre doit couvrir tout l'horizon de la page (10 semaines = 70 nuits),
/// donc un calcul propre à cette page plutôt qu'une dépendance sur l'état
/// du service partagé.
@Observable
@MainActor
final class CorrelationChargeTIRService {

    private(set) var synthese: SyntheseCorrelationChargeTIR?

    /// `true` pendant le recalcul — pilote le spinner de la carte sommaire,
    /// qui reste affichée (jamais cachée) pendant ce temps.
    private(set) var enCalcul = false

    func demarrer(contexte: ModelContext) async {
        await recalculer(contexte: contexte)
    }

    /// Le fetch (I/O, a besoin du `ModelContext`) reste sur le `MainActor` ;
    /// l'assemblage (`CalculAnalyseBasale.analyser` +
    /// `CalculCorrelationChargeTIR.analyser`, purs et `Sendable`) est déporté
    /// sur une tâche détachée pour ne pas bloquer le thread principal pendant
    /// la segmentation des 70 nuits — même correctif que `AnalyseBasaleService`
    /// pour le lag perçu au changement d'onglet.
    func recalculer(contexte: ModelContext) async {
        enCalcul = true
        let borne = Calendar.current.date(
            byAdding: .day, value: -7 * CalculCorrelationChargeTIR.nombreSemaines, to: Date()
        ) ?? Date()

        let glucoses = (try? contexte.fetch(
            FetchDescriptor<GlucoseReading>(predicate: #Predicate { $0.date >= borne })
        )) ?? []

        let typeLente = TypeInsuline.lente
        let lentes = (try? contexte.fetch(
            FetchDescriptor<Injection>(predicate: #Predicate { $0.heure >= borne && $0.type == typeLente })
        )) ?? []

        let (entrees, config) = chargerEntreesB1(contexte: contexte, borne: borne)

        let charge = ChargeActiveService.shared.contexte ?? .vide
        let glucosesMappes = glucoses.map { (date: $0.date, valeur: $0.valeur) }
        let lentesMappees = lentes.map { (date: $0.heure, dose: $0.dose) }

        synthese = await Task.detached(priority: .userInitiated) {
            let detail = CalculAnalyseBasale.analyser(entrees: entrees, config: config)
            let nuitsDerive = Self.deriveNuits(depuis: detail)
            return CalculCorrelationChargeTIR.analyser(
                charge: charge,
                glucoses: glucosesMappes,
                lentes: lentesMappees,
                nuitsDerive: nuitsDerive
            )
        }.value
        enCalcul = false
    }

    /// Dérive de zone 3 (nuit profonde) par nuit — extrait du détail B1 déjà
    /// assemblé. Pur, exécuté sur la tâche détachée avec `analyser`.
    private nonisolated static func deriveNuits(depuis detail: AnalyseBasaleDetail) -> [(date: Date, derive: Double)] {
        detail.nightChartData.compactMap { nuit -> (date: Date, derive: Double)? in
            guard let zone3 = nuit.zones.first(where: { $0.zone == .nuitProfonde }),
                  zone3.isAnalyzed, let pente = zone3.slope
            else { return nil }
            let heures = zone3.timeRange.upperBound.timeIntervalSince(zone3.timeRange.lowerBound) / 3600
            return (date: nuit.date, derive: pente * heures)
        }
    }

    // MARK: - Faits B1 (fenêtre élargie)

    private func chargerEntreesB1(contexte: ModelContext, borne: Date) -> (EntreesBasale, ConfigBasale) {
        let cal = Calendar.current
        let nombreNuits = CalculCorrelationChargeTIR.nombreSemaines * 7
        // Marge zone 1 (pré-endormissement) + historique de dose, même esprit
        // que `AnalyseBasaleService.chargerEntrees` mais sur l'horizon élargi.
        let borneFaits = cal.date(byAdding: .day, value: -1, to: borne) ?? borne
        let borneDose = cal.date(byAdding: .day, value: -30, to: borne) ?? borne

        var cgmDescriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= borneFaits },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        cgmDescriptor.propertiesToFetch = [\.date, \.valeur]
        let cgm = ((try? contexte.fetch(cgmDescriptor)) ?? []).map { (date: $0.date, valeur: $0.valeur) }

        let injections = (try? contexte.fetch(
            FetchDescriptor<Injection>(predicate: #Predicate { $0.heure >= borneDose })
        )) ?? []
        let lentes = injections.filter { $0.type == .lente }.map { (heure: $0.heure, dose: $0.dose) }
        let rapides = injections.filter { $0.type != .lente }.map {
            (heure: $0.heure, dose: $0.dose, correction: $0.type == .rapideCorrection || $0.motif == .correction)
        }

        let repas = ChargeurFaitsCoucher.repasHorsResucrage(contexte, depuis: borneFaits)
        let resucrages = ChargeurFaitsCoucher.resucrages(contexte, depuis: borneFaits)

        let sports = (try? contexte.fetch(
            FetchDescriptor<ActiviteSportive>(predicate: #Predicate { $0.dateDebut >= borneFaits })
        )).map { $0.map { (debut: $0.dateDebut, dureeMin: $0.dureeMinutes) } } ?? []

        let pauses = ((try? contexte.fetch(FetchDescriptor<PeriodePause>())) ?? [])
            .filter { ($0.fin ?? Date()) >= borneFaits }
            .map { (debut: $0.debut, fin: $0.fin) }

        let entrees = EntreesBasale(
            lectures: cgm, lentes: lentes, rapides: rapides,
            repas: repas, resucrages: resucrages, sports: sports, pauses: pauses
        )

        let profil = ProfilService.shared.profil
        var config = ConfigBasale(
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        config.seuilHypo = Int(profil.seuilsGlycemiques.hypoglycemie)
        config.seuilHyper = Int(profil.seuilsGlycemiques.hyperglycemie)
        config.fenetreNuits = nombreNuits

        return (entrees, config)
    }
}

#if DEBUG
extension CorrelationChargeTIRService {

    @MainActor
    static func apercu(synthese: SyntheseCorrelationChargeTIR = .mock) -> CorrelationChargeTIRService {
        let service = CorrelationChargeTIRService()
        service.synthese = synthese
        return service
    }
}

extension SyntheseCorrelationChargeTIR {

    static var mock: SyntheseCorrelationChargeTIR {
        let cal = Calendar.current
        let debut = cal.date(byAdding: .day, value: -7 * (CalculCorrelationChargeTIR.nombreSemaines - 1), to: Date()) ?? Date()
        let charges: [Double?] = [0.6, 0.9, 1.3, 1.5, 0.5, 0.4, 0.35, 1.2, 1.4, 1.0]
        let tirs: [Double?] = [62, 68, 74, 77, 58, 54, 51, 72, 76, 65]
        let scores: [Double?] = [70, 74, 80, 83, 66, 60, 58, 78, 82, 72]
        let semaines = (0..<CalculCorrelationChargeTIR.nombreSemaines).map { i in
            PointSemaineCorrelation(
                debutSemaine: cal.date(byAdding: .day, value: 7 * i, to: debut) ?? debut,
                indiceCharge: charges[i],
                tir: tirs[i],
                score: scores[i]
            )
        }
        return SyntheseCorrelationChargeTIR(
            semaines: semaines,
            changementsDose: [
                MarqueurChangementDose(
                    date: cal.date(byAdding: .day, value: 7 * 4, to: debut) ?? debut,
                    dose: 20
                )
            ],
            tranches: [
                TrancheChargeTIR(niveau: .basse, tirMoyen: 54, nombreJours: 18),
                TrancheChargeTIR(niveau: .normale, tirMoyen: 65, nombreJours: 31),
                TrancheChargeTIR(niveau: .haute, tirMoyen: 75, nombreJours: 16),
            ],
            tranchesDerive: [
                TrancheDeriveBasale(niveau: .basse, deriveMoyenne: 18, nombreNuits: 5),
                TrancheDeriveBasale(niveau: .normale, deriveMoyenne: 3, nombreNuits: 9),
                TrancheDeriveBasale(niveau: .haute, deriveMoyenne: -9, nombreNuits: 4),
            ]
        )
    }
}
#endif
