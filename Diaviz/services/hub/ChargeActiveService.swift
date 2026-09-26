//
//  ChargeActiveService.swift
//  diaviz
//

import Foundation
import Observation
import OSLog
import SwiftData

/// Service **réel** et **partagé** de la charge active — seule source de
/// charge de l'app. Rassemble séances du hub, workouts et pas d'Apple Santé,
/// délègue à `CalculChargeActive` (pur) et expose un `ContexteChargeActive`
/// lu par tous les écrans : accueil (faits), page Charge et glycémie, badges
/// (repas, nuit B1), B2/B3 et la recherche du coucher. Rien n'est persisté.
///
/// Singleton comme `ProfilService` : des calculateurs statiques
/// (`InsightsService`, `RechercheCoucher`) et plusieurs services en ont
/// besoin hors de la hiérarchie de vues.
@Observable
@MainActor
final class ChargeActiveService {

    static let shared = ChargeActiveService()

    /// `nil` avant le premier calcul.
    private(set) var contexte: ContexteChargeActive?
    /// Lecture à l'instant du dernier calcul.
    private(set) var synthese: SyntheseChargeActive?
    private(set) var enCalcul = false

    private let lecteur = HealthKitChargeActiveLecteur()

    /// Faits Apple Santé du dernier passage complet — réutilisés quand seules
    /// les séances du hub changent (saisie, import), pour ne pas relire des
    /// mois de pas à chaque mutation.
    private var cacheSante: (workouts: [WorkoutPourCharge], bouts: [BoutMarche]?, premierPas: Date?)?
    private var dernierPassageComplet: Date?

    /// Au-delà, un retour sur l'onglet Analyses relit Apple Santé.
    static let fraicheurSante: TimeInterval = 15 * 60

    /// Passage complet : Apple Santé (pas, workouts, FC) + hub.
    func recalculer(contexte modelContext: ModelContext) async {
        enCalcul = true
        defer { enCalcul = false }

        let maintenant = Date()
        let borne = Self.borne(maintenant)
        let fenetre = DateInterval(start: borne, end: maintenant)

        await lecteur.demanderAcces()
        // Lectures indépendantes lancées ensemble.
        async let workoutsLus = lecteur.workouts(sur: DateInterval(start: Self.borneHub(borne), end: maintenant))
        async let premierPasLu = lecteur.premierPas()
        async let heuresLues = lecteur.pasParHeure(sur: fenetre)
        let (workouts, premierPas, heures) = await (workoutsLus, premierPasLu, heuresLues)
        var bouts: [BoutMarche]?
        if premierPas != nil {
            let plages = CalculChargeActive.plagesCandidates(pasParHeure: heures)
            bouts = CalculChargeActive.boutsMarche(pasParMinute: await lecteur.pasParMinute(plages: plages))
        }
        cacheSante = (workouts, bouts, premierPas)
        dernierPassageComplet = maintenant
        await assembler(modelContext: modelContext, maintenant: maintenant)
    }

    /// Retour sur un écran : relit Apple Santé seulement si le dernier
    /// passage complet date de plus de `fraicheurSante`, sinon réassemble
    /// avec les faits en cache (quasi instantané).
    func recalculerSiNecessaire(contexte modelContext: ModelContext) async {
        if let dernierPassageComplet, Date().timeIntervalSince(dernierPassageComplet) < Self.fraicheurSante {
            await assembler(modelContext: modelContext, maintenant: Date())
        } else {
            await recalculer(contexte: modelContext)
        }
    }

    /// Séances du hub modifiées : réassemble avec les faits Santé en cache.
    /// Sans passage complet préalable, ne fait rien : le démarrage
    /// (`AppTabVues`) s'en charge après l'autorisation Santé groupée.
    func actualiserSeances(contexte modelContext: ModelContext) async {
        guard cacheSante != nil else { return }
        await assembler(modelContext: modelContext, maintenant: Date())
    }

    // MARK: - Assemblage

    private static func borne(_ maintenant: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -CalculChargeActive.profondeurJours, to: maintenant) ?? maintenant
    }

    /// Marge d'un jour : une longue séance commencée avant la borne peut
    /// chevaucher un bout de marche de la fenêtre.
    private static func borneHub(_ borne: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: borne) ?? borne
    }

    private func assembler(modelContext: ModelContext, maintenant: Date) async {
        let sante = cacheSante ?? ([], nil, nil)
        let borneHub = Self.borneHub(Self.borne(maintenant))
        let activites = (try? modelContext.fetch(
            FetchDescriptor<ActiviteSportive>(predicate: #Predicate { $0.dateDebut >= borneHub })
        )) ?? []
        var premiere = FetchDescriptor<ActiviteSportive>(sortBy: [SortDescriptor(\.dateDebut, order: .forward)])
        premiere.fetchLimit = 1
        let premiereSeance = (try? modelContext.fetch(premiere))?.first?.dateDebut

        // Jointure hub ↔ workouts : type d'activité et FC lus à la volée
        // (repli sur la FC figée à l'import).
        let workoutsParUUID = Dictionary(sante.workouts.map { ($0.uuid, $0) }, uniquingKeysWith: { premier, _ in premier })
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
            + sante.workouts.map(\.intervalle)
        let bouts = sante.bouts.map { CalculChargeActive.exclureChevauchements($0, seances: intervallesSeances) }
        let debutHistorique = CalculChargeActive.debutHistorique(premierPas: sante.premierPas, premiereSeance: premiereSeance)

        Logger.sante.info("Charge active : \(seances.count, privacy: .public) séances, \(bouts?.count ?? -1, privacy: .public) bouts de marche")

        let resultat = await Task.detached(priority: .userInitiated) {
            let contexte = CalculChargeActive.contexte(
                seances: seances, bouts: bouts, debutHistorique: debutHistorique, maintenant: maintenant
            )
            return (contexte, contexte.synthese(a: maintenant))
        }.value
        contexte = resultat.0
        synthese = resultat.1
    }
}

#if DEBUG
extension ContexteChargeActive {

    /// Deux semaines de faits : séances régulières puis semaine plus calme,
    /// marche soutenue presque tous les jours.
    static var mock: ContexteChargeActive {
        let cal = Calendar.current
        let aujourdhui = cal.startOfDay(for: Date())
        let seances: [Double] = [45, 0, 60, 0, 50, 90, 0, 30, 0, 0, 40, 0, 0, 0]
        let marche: [Double] = [25, 40, 0, 15, 30, 0, 55, 20, 35, 0, 25, 40, 10, 30]
        let niveaux: [NiveauChargeActive] = Array(repeating: .normale, count: 10) + Array(repeating: .basse, count: 4)
        let jours = (0..<14).map { i in
            JourChargeActive(
                jour: cal.date(byAdding: .day, value: -(13 - i), to: aujourdhui) ?? aujourdhui,
                nombreSeances: seances[i] > 0 ? 1 : 0,
                minutesSeances: seances[i],
                minutesMarche: marche[i],
                indice: nil,
                niveau: niveaux[i],
                depuisJours: i >= 10 ? i - 9 : nil
            )
        }
        return ContexteChargeActive(
            contributions: [], debutHistorique: nil, marcheIncluse: true, jours: jours, calendrier: cal
        )
    }
}
#endif
