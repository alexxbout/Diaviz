//
//  CorrelationChargeTIRService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service de la page « Charge et glycémie » — lit le contexte partagé de
/// charge active (`ChargeActiveService`, à calculer avant), les glycémies,
/// les nuits et les repas, puis délègue aux calculateurs purs : la
/// chronologie (`CalculCorrelationChargeTIR`) et les épisodes de charge
/// (`CalculEpisodesCharge`, C1).
///
/// Fait tourner `CalculAnalyseBasale` **une deuxième fois**, séparément du
/// service B1 partagé (`AnalyseBasaleService`, 14 nuits) : les épisodes ont
/// besoin des nuits de tout l'horizon de charge (90 jours).
@Observable
@MainActor
final class CorrelationChargeTIRService {

    private(set) var synthese: SyntheseCorrelationChargeTIR?

    /// Épisodes de charge et état des réglages (C1) — `nil` avant le premier
    /// calcul.
    private(set) var episodes: SyntheseEpisodesCharge?

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
        let maintenant = Date()
        let cal = Calendar.current
        let borne = cal.date(
            byAdding: .day, value: -7 * CalculCorrelationChargeTIR.nombreSemaines, to: maintenant
        ) ?? maintenant
        // Les épisodes couvrent tout l'horizon du contexte de charge.
        let borneEpisodes = cal.date(
            byAdding: .day, value: -CalculChargeActive.horizonJours, to: cal.startOfDay(for: maintenant)
        ) ?? borne

        var descripteurCGM = FetchDescriptor<GlucoseReading>(predicate: #Predicate { $0.date >= borneEpisodes })
        descripteurCGM.propertiesToFetch = [\.date, \.valeur]
        let glycemies = ((try? contexte.fetch(descripteurCGM)) ?? []).map { MesureGlycemie(date: $0.date, valeur: $0.valeur) }

        let (entrees, config) = chargerEntreesB1(contexte: contexte, borne: borneEpisodes)

        let charge = ChargeActiveService.shared.contexte ?? .vide
        let glucosesMappes = glycemies.filter { $0.date >= borne }.map { (date: $0.date, valeur: $0.valeur) }

        let profil = ProfilService.shared.profil
        let evenementsRepas = ChargeurEpisodesCharge.evenementsRepas(contexte, depuis: borneEpisodes, profil: profil)
        var valeursActuelles = ChargeurEpisodesCharge.valeursActuelles(profil: profil)
        if let lente = entrees.lentes.max(by: { $0.heure < $1.heure }) {
            valeursActuelles[.lente] = lente.dose
        }
        let resucrages = ChargeurFaitsCoucher.resucrages(contexte, depuis: borneEpisodes).map(\.heure)

        let (correlation, episodes) = await Task.detached(priority: .userInitiated) {
            let detail = CalculAnalyseBasale.analyser(entrees: entrees, config: config, maintenant: maintenant)
            let correlation = CalculCorrelationChargeTIR.analyser(
                charge: charge,
                glucoses: glucosesMappes,
                maintenant: maintenant
            )
            let episodes = CalculEpisodesCharge.analyser(
                charge: charge,
                evenements: ChargeurEpisodesCharge.evenementsNuits(detail.nightChartData) + evenementsRepas,
                valeursActuelles: valeursActuelles,
                glycemies: glycemies,
                resucrages: resucrages,
                maintenant: maintenant
            )
            return (correlation, episodes)
        }.value
        synthese = correlation
        self.episodes = episodes
        enCalcul = false
    }

    // MARK: - Faits B1 (fenêtre élargie)

    private func chargerEntreesB1(contexte: ModelContext, borne: Date) -> (EntreesBasale, ConfigBasale) {
        let cal = Calendar.current
        let nombreNuits = cal.dateComponents([.day], from: cal.startOfDay(for: borne), to: cal.startOfDay(for: Date())).day.map { $0 + 1 } ?? CalculChargeActive.horizonJours
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
        config.classementsManuels = profil.preferencesAvancees.classementsNuits ?? [:]
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
        return SyntheseCorrelationChargeTIR(semaines: semaines)
    }
}
#endif
