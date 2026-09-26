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
    /// Passage complet en cours : un second appel l'attend au lieu de
    /// relancer les mêmes lectures Santé en parallèle.
    private var passageEnCours: Task<Void, Never>?

    /// Au-delà, un retour sur l'onglet Analyses relit Apple Santé.
    static let fraicheurSante: TimeInterval = 15 * 60

    /// Passage complet : Apple Santé (pas, workouts, FC) + hub.
    func recalculer(contexte modelContext: ModelContext) async {
        if let passageEnCours {
            await passageEnCours.value
            return
        }
        let passage = Task { await passageComplet(modelContext: modelContext) }
        passageEnCours = passage
        await passage.value
        passageEnCours = nil
    }

    /// Au démarrage, avant le préflight Santé : lance le passage complet
    /// tout de suite si l'autorisation est déjà tranchée (cas courant, hors
    /// premier lancement), pour que l'accueil n'attende pas la synchro CGM.
    func demarrerSiAutorise(contexte modelContext: ModelContext) async {
        guard await lecteur.autorisationTranchee() else { return }
        await recalculer(contexte: modelContext)
    }

    // MARK: - Cache des bouts de marche

    /// Bouts de marche des **jours clos** (jusqu'à `couvertJusqua`), gardés
    /// d'un lancement à l'autre : les pas d'une journée passée ne changent
    /// plus, les relire à la minute coûtait ~7 s à chaque démarrage.
    ///
    /// `UserDefaults` est légitime ici (règle du CLAUDE.md) : faits dérivés
    /// d'Apple Santé, propres à l'appareil, jamais une saisie. Perdus, ils
    /// sont simplement recalculés au passage suivant.
    private struct CacheBoutsMarche: Codable {
        let couvertJusqua: Date
        let bouts: [BoutMarche]
    }

    /// Versionnée : changer la détection (cadence, durée, coefficient…)
    /// impose de changer la clé, sinon les anciens bouts resteraient servis.
    private static let cleCacheBouts = "chargeActive.cacheBoutsMarche.v1"
    /// Les deux derniers jours restent relus : la montre synchronise parfois
    /// ses pas avec plusieurs heures de retard.
    private static let joursNonClos = 2

    private static func lireCacheBouts() -> CacheBoutsMarche? {
        guard let data = UserDefaults.standard.data(forKey: cleCacheBouts) else { return nil }
        return try? JSONDecoder().decode(CacheBoutsMarche.self, from: data)
    }

    private static func ecrireCacheBouts(_ cache: CacheBoutsMarche) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: cleCacheBouts)
    }

    private func passageComplet(modelContext: ModelContext) async {
        enCalcul = true
        defer { enCalcul = false }
        let chrono = ContinuousClock.now

        let maintenant = Date()
        let borne = Self.borne(maintenant)
        let coupure = Calendar.current.date(
            byAdding: .day, value: -Self.joursNonClos, to: Calendar.current.startOfDay(for: maintenant)
        ) ?? maintenant
        // Cache utilisable s'il couvre bien toute la fenêtre jusqu'à sa
        // coupure : on ne relit alors que depuis celle-ci.
        let cache = Self.lireCacheBouts().flatMap { $0.couvertJusqua > borne ? $0 : nil }
        let debutLecture = min(cache?.couvertJusqua ?? borne, coupure)
        let fenetre = DateInterval(start: max(debutLecture, borne), end: maintenant)

        await lecteur.demanderAcces()
        // Lectures indépendantes lancées ensemble, chronométrées une à une.
        async let workoutsLus = Self.chronometrer { await self.lecteur.workouts(sur: DateInterval(start: Self.borneHub(borne), end: maintenant)) }
        async let premierPasLu = Self.chronometrer { await self.lecteur.premierPas(borne: borne) }
        async let blocsLus = Self.chronometrer { await self.lecteur.pasParBloc(sur: fenetre) }
        let (workoutsMesure, premierPasMesure, blocsMesure) = await (workoutsLus, premierPasLu, blocsLus)
        let (workouts, premierPas, blocs) = (workoutsMesure.0, premierPasMesure.0, blocsMesure.0)
        let tLectures = ContinuousClock.now
        Logger.sante.info("Charge active chrono lectures : workouts \(Self.ms(workoutsMesure.1), privacy: .public), premier pas \(Self.ms(premierPasMesure.1), privacy: .public), blocs 10 min \(Self.ms(blocsMesure.1), privacy: .public)")
        var bouts: [BoutMarche]?
        var nombrePlages = 0
        if premierPas != nil {
            let plages = CalculChargeActive.plagesCandidates(pasParBloc: blocs)
            nombrePlages = plages.count
            let relus = CalculChargeActive.boutsMarche(pasParMinute: await lecteur.pasParMinute(plages: plages))
            let tous = cache.map {
                CalculChargeActive.fusionnerBouts(cache: $0.bouts, nouveaux: relus, coupure: $0.couvertJusqua)
            } ?? relus
            bouts = tous.filter { $0.fin >= borne }
            Self.ecrireCacheBouts(CacheBoutsMarche(
                couvertJusqua: coupure, bouts: tous.filter { $0.debut < coupure && $0.fin >= borne }
            ))
        }
        let tMinutes = ContinuousClock.now
        cacheSante = (workouts, bouts, premierPas)
        dernierPassageComplet = maintenant
        await assembler(modelContext: modelContext, maintenant: maintenant)
        let fin = ContinuousClock.now
        Logger.sante.info("Charge active chrono : lectures \(Self.ms(tLectures - chrono), privacy: .public), \(nombrePlages, privacy: .public) plages minute \(Self.ms(tMinutes - tLectures), privacy: .public), assemblage \(Self.ms(fin - tMinutes), privacy: .public)")
    }

    private static func chronometrer<T>(_ lecture: () async -> T) async -> (T, Duration) {
        let debut = ContinuousClock.now
        let valeur = await lecture()
        return (valeur, ContinuousClock.now - debut)
    }

    private nonisolated static func ms(_ duree: Duration) -> String {
        duree.formatted(.units(allowed: [.milliseconds]))
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
