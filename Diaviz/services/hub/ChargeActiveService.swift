//
//  ChargeActiveService.swift
//  diaviz
//

import Foundation
import Observation
import OSLog
import SwiftData

/// Service **réel** de la charge active — rassemble séances du hub, workouts
/// et pas d'Apple Santé, puis délègue à `CalculChargeActive` (pur). Rien
/// n'est persisté : recalcul à chaque apparition de la page Analyses.
///
/// Seul consommateur : la page « Charge et glycémie » (indice + niveau), en
/// phase d'observation avant la frise des périodes (C1).
@Observable
@MainActor
final class ChargeActiveService {

    private(set) var synthese: SyntheseChargeActive?
    private(set) var enCalcul = false

    private let lecteur = HealthKitChargeActiveLecteur()

    func recalculer(contexte: ModelContext) async {
        enCalcul = true
        defer { enCalcul = false }

        let maintenant = Date()
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -CalculChargeActive.profondeurJours, to: maintenant) ?? maintenant
        let fenetre = DateInterval(start: borne, end: maintenant)

        // Hub — marge d'un jour : une longue séance commencée avant la borne
        // peut chevaucher un bout de marche de la fenêtre.
        let borneHub = cal.date(byAdding: .day, value: -1, to: borne) ?? borne
        let activites = (try? contexte.fetch(
            FetchDescriptor<ActiviteSportive>(predicate: #Predicate { $0.dateDebut >= borneHub })
        )) ?? []
        var premiere = FetchDescriptor<ActiviteSportive>(sortBy: [SortDescriptor(\.dateDebut, order: .forward)])
        premiere.fetchLimit = 1
        let premiereSeance = (try? contexte.fetch(premiere))?.first?.dateDebut

        // Apple Santé.
        await lecteur.demanderAcces()
        let workouts = await lecteur.workouts(sur: DateInterval(start: borneHub, end: maintenant))
        let premierPas = await lecteur.premierPas()
        var boutsDetectes: [BoutMarche]?
        if premierPas != nil {
            let plages = CalculChargeActive.plagesCandidates(pasParHeure: await lecteur.pasParHeure(sur: fenetre))
            let minutes = await lecteur.pasParMinute(plages: plages)
            boutsDetectes = CalculChargeActive.boutsMarche(pasParMinute: minutes)
        }

        // Jointure hub ↔ workouts : type d'activité et FC lus à la volée
        // (repli sur la FC figée à l'import).
        let workoutsParUUID = Dictionary(workouts.map { ($0.uuid, $0) }, uniquingKeysWith: { premier, _ in premier })
        let seances = activites.map { activite -> SeancePourCharge in
            let workout = activite.healthKitData.flatMap { workoutsParUUID[$0.workoutUUID] }
            return SeancePourCharge(
                debut: activite.dateDebut,
                dureeMin: activite.dureeMinutes,
                intensite: activite.intensite,
                fcMoyenne: workout?.fcMoyenne ?? activite.healthKitData?.fcMoyenne,
                typeActiviteHK: workout?.typeActiviteHK
            )
        }

        let intervallesSeances = seances.map { DateInterval(start: $0.debut, end: $0.fin) }
            + workouts.map(\.intervalle)
        let bouts = boutsDetectes.map {
            CalculChargeActive.exclureChevauchements($0, seances: intervallesSeances)
        }
        let debutHistorique = [premierPas, premiereSeance].compactMap { $0 }.min()

        Logger.sante.info("Charge active : \(seances.count, privacy: .public) séances, \(bouts?.count ?? -1, privacy: .public) bouts de marche")

        synthese = await Task.detached(priority: .userInitiated) {
            CalculChargeActive.analyser(
                seances: seances, bouts: bouts, debutHistorique: debutHistorique, maintenant: maintenant
            )
        }.value
    }
}
