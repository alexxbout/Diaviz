//
//  ScoreService.swift
//  diaviz
//
//  Created by Alexandre on 20/06/2026.
//

import Foundation
import Observation
import SwiftData

/// Score quotidien complet — `FaitsJour` (score + décomposition GRI) ancré à un
/// jour calendaire. Les pourcentages sont la source de vérité ; les durées sont
/// dérivées (24h × %) pour l'affichage.
struct ScoreJournalier: Sendable, Equatable, Hashable {
    /// Jour calendaire (00:00 local) auquel ce score se rapporte.
    let jour: Date

    /// Faits du jour — score et métriques GRI.
    let faits: FaitsJour

    /// Score 0–100 — convenience.
    var score: Int { faits.score }

    /// Durée d'une journée standardisée (24h) — base des conversions % → durée.
    static let dureeJourSec: TimeInterval = 24 * 60 * 60

    /// Convertit un pourcentage (0–100) en durée (secondes).
    static func duree(pourPourcent pct: Double) -> TimeInterval {
        max(0, pct) / 100.0 * dureeJourSec
    }
}

/// Service **réel** du score quotidien : lit les `GlucoseReading` du hub,
/// découpe en jours métaboliques (06h→06h) et délègue le calcul GRI à
/// `CalculScoreJournalier` (assembleur pur).
///
/// API publique **identique** à `ScoreJournalierServiceMock` afin que les vues
/// (carte d'accueil) puissent basculer sans changer leur surface de
/// consommation. La différence est interne : ici les `FaitsJour` proviennent de
/// données CGM réelles, là le mock les générait algorithmiquement.
///
/// Convention « un hub, des dérivations » : aucun score n'est persisté. Le
/// contexte est injecté au boot via `.task { demarrer(contexte:) }`, les jours
/// consolidés sont recalculés une fois ; le jour en cours (`scoreDuJour`,
/// `partielDuJour`) est recalculé à chaque accès depuis le cache d'échantillons.
@Observable
@MainActor
final class ScoreService {

    /// Échantillons CGM bruts chargés depuis le hub, sur la fenêtre des 30
    /// derniers jours métaboliques (du plus ancien au plus récent). Source de
    /// vérité unique du service ; tout le reste en dérive.
    private(set) var echantillons: [(date: Date, valeur: Int)] = []

    /// Scores consolidés des jours **terminés** (J-30 … J-1), du plus ancien au
    /// plus récent. Le jour en cours est exclu (calculé en temps réel).
    private(set) var scores: [ScoreJournalier] = []

    /// Contexte SwiftData injecté au boot. Conservé pour d'éventuels
    /// rechargements (changement de jour, nouvelle ingestion).
    private var contexte: ModelContext?

    init() {}

    // MARK: - Boot

    /// Injecte le contexte du hub et charge les 30 derniers jours. Appelé une
    /// fois depuis `.task` à l'apparition de la vue d'accueil.
    func demarrer(contexte: ModelContext) {
        self.contexte = contexte
        recharger()
    }

    /// Recharge les échantillons depuis le hub et reconstruit les scores
    /// consolidés. Idempotent : peut être rappelé après une ingestion.
    func recharger() {
        guard let contexte else { return }
        echantillons = chargerEchantillons(contexte: contexte)
        scores = consoliderJours()
    }

    // MARK: - Lecture (API publique identique au mock)

    /// Score consolidé pour un jour donné (`isDate(:inSameDayAs:)`), ou `nil` si
    /// hors des 30 derniers jours / couverture insuffisante.
    func score(pour jour: Date) -> ScoreJournalier? {
        let cal = Calendar.current
        return scores.first { cal.isDate($0.jour, inSameDayAs: jour) }
    }

    /// 7 jours menant jusqu'au jour donné inclus (J-6 → jour). Les jours sans
    /// donnée exploitable retournent `nil` (barres atténuées). Si `jour` est le
    /// jour courant, on substitue le score partiel temps réel.
    func historiqueSept(jusquA jour: Date) -> [(jour: Date, score: Int?)] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: jour)
        return (0..<7).reversed().compactMap { decalage in
            guard let j = cal.date(byAdding: .day, value: -decalage, to: base) else {
                return nil
            }
            if estJourCourant(j) {
                return (j, scoreDuJour)
            }
            return (j, score(pour: j)?.score)
        }
    }

    /// Plage navigable : les jours des 30 derniers à couverture suffisante, du
    /// plus ancien au plus récent. Le jour en cours n'y figure pas (pas de
    /// score consolidé tant que la journée n'est pas finie).
    var joursNavigables: [Date] {
        scores.map(\.jour).sorted()
    }

    // MARK: - Jour métabolique (convention 06h-06h)

    /// Début du **jour métabolique** contenant `date` (06h locale). Avant 06h,
    /// on est encore dans le jour métabolique de la veille. Helper recopié à
    /// l'identique depuis le mock pour cohérence avec la couche d'analyses.
    nonisolated static func debutJourMetabolique(pour date: Date = Date()) -> Date {
        let cal = Calendar.current
        let sixHeures = cal.date(
            bySettingHour: 6, minute: 0, second: 0, of: date
        ) ?? date
        if date < sixHeures {
            return cal.date(byAdding: .day, value: -1, to: sixHeures) ?? sixHeures
        }
        return sixHeures
    }

    /// Jour calendaire du **jour métabolique en cours** : le jour où la fenêtre
    /// 06h→06h a commencé. Avant 06h, c'est encore « hier » (la nuit appartient à
    /// la veille). C'est LUI le « jour en cours » du score — pas le jour
    /// calendaire courant. Évite d'afficher le jour suivant avant 06h.
    var jourCourant: Date {
        Calendar.current.startOfDay(for: Self.debutJourMetabolique(pour: Date()))
    }

    /// `true` si `jour` est le jour métabolique en cours.
    func estJourCourant(_ jour: Date) -> Bool {
        Calendar.current.isDate(jour, inSameDayAs: jourCourant)
    }

    /// Heures écoulées depuis le début du jour métabolique courant, bornées
    /// [0, 24].
    var heuresDataDuJour: Double {
        let now = Date()
        let debut = Self.debutJourMetabolique(pour: now)
        return max(0, min(24, now.timeIntervalSince(debut) / 3600))
    }

    /// Fenêtre métabolique (06h→06h) du jour calendaire donné. Pour le jour en
    /// cours, la borne haute est `maintenant` plutôt que +24h (fenêtre
    /// tronquée, cohérent avec `partielDuJour`).
    func fenetreMetabolique(pourJourCalendaire jour: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        let debut = cal.date(byAdding: .hour, value: 6, to: cal.startOfDay(for: jour)) ?? jour
        if estJourCourant(jour) {
            return debut...max(debut, Date())
        }
        return debut...debut.addingTimeInterval(ScoreJournalier.dureeJourSec)
    }

    /// Échantillons CGM bruts du jour calendaire donné, filtrés sur sa fenêtre
    /// métabolique. Source pour l'empreinte glycémique (aucune persistance
    /// dédiée — recalculé à la volée depuis `echantillons`).
    func echantillonsPourJour(_ jour: Date) -> [(date: Date, valeur: Int)] {
        let fenetre = fenetreMetabolique(pourJourCalendaire: jour)
        return echantillons.filter { fenetre.contains($0.date) }
    }

    /// Score à afficher pour un jour donné, avec le même traitement spécial
    /// du jour en cours que `scoreCourant` dans `DetailScoreVue` : score
    /// partiel seulement s'il est significatif (sinon `nil`, jamais un faux
    /// 0). Centralisé ici pour que la sheet d'empreinte (qui navigue jour
    /// par jour) n'ait pas à dupliquer cette logique.
    func scoreAffiche(pour jour: Date) -> Int? {
        if estJourCourant(jour) {
            return jourCourantSignificatif ? scoreDuJour : nil
        }
        return score(pour: jour)?.score
    }

    // MARK: - Jour en cours

    /// Score partiel du jour métabolique en cours, recalculé à chaque accès
    /// depuis les échantillons chargés. `0` quand la fenêtre est vide ou la
    /// couverture trop faible (cohérent avec la signature non-optionnelle du
    /// mock : la carte affiche alors un score plancher, le sous-texte
    /// « Xh de données » signale la jeunesse de la journée).
    var scoreDuJour: Int {
        partielDuJour.score
    }

    /// Heures de données CGM **réelles** accumulées dans le jour métabolique en
    /// cours. ≠ heures écoulées : avec le différé Dexcom (~3h), bien moindre le
    /// matin (aucune donnée du jour avant ~9h).
    var heuresDonneesJourCourant: Double {
        let debut = Self.debutJourMetabolique(pour: Date())
        let n = echantillons.filter { $0.date >= debut }.count
        return Double(n) * CalculScoreJournalier.intervalleEchantillonSec / 3600
    }

    /// Le jour en cours a-t-il assez de données pour un score **représentatif**
    /// (≥ 6h de CGM réelles) ? En-deçà, on préfère mettre en avant le dernier
    /// jour complet plutôt qu'un score partiel trompeur (« 0 » le matin).
    var jourCourantSignificatif: Bool {
        heuresDonneesJourCourant >= 6
    }

    /// Score du jour en cours s'il est significatif, sinon `nil` (affichage
    /// « — » au lieu d'un faux « 0 »).
    var scoreDuJourSignificatif: Int? {
        jourCourantSignificatif ? scoreDuJour : nil
    }

    /// Jour à mettre en avant sur l'accueil : le jour en cours s'il est
    /// significatif, sinon le **dernier jour consolidé** (bascule sur la veille).
    var jourAffiche: Date {
        jourCourantSignificatif ? jourCourant : (joursNavigables.last ?? jourCourant)
    }

    /// Score de `jourAffiche` (nil si aucun jour exploitable).
    var scoreAffiche: Int? {
        jourCourantSignificatif ? scoreDuJour : score(pour: jourAffiche)?.score
    }

    /// `ScoreJournalier` partiel d'aujourd'hui — fenêtre du jour métabolique
    /// courant tronquée à l'instant présent. Couverture attendue réduite à la
    /// durée écoulée (pas 24h), pour ne pas pénaliser une journée qui commence.
    /// Retombe sur des `FaitsJour` neutres si la couverture est insuffisante.
    var partielDuJour: ScoreJournalier {
        let now = Date()
        let debut = Self.debutJourMetabolique(pour: now)
        let fenetre = debut...max(debut, now)
        let faits = CalculScoreJournalier.faits(
            depuis: echantillons, fenetre: fenetre, couvertureMin: Self.couvertureMinAffichage
        ) ?? Self.faitsNeutres
        return ScoreJournalier(jour: jourCourant, faits: faits)
    }

    // MARK: - Consolidation des jours terminés

    /// Reconstruit les scores des 30 jours métaboliques **terminés** précédant
    /// aujourd'hui (J-30 … J-1). Un jour sans couverture suffisante est omis
    /// (dégradation gracieuse) — il apparaîtra en barre atténuée côté carte.
    /// Seuil de couverture CGM pour qu'un jour soit affiché (consolidé ou jour en
    /// cours). Plus permissif que le 70 % « clinique » : sur device réel (différé
    /// Dexcom ~3h qui laisse un trou récent + warmup capteur + pertes signal),
    /// beaucoup de jours valides tombent sous 70 % et disparaîtraient (barres
    /// vides / score 0). 50 % garde un score exploitable tout en écartant les
    /// jours quasi vides. Distinct du seuil « significatif » du jour en cours
    /// (≥ 6h de données réelles).
    static let couvertureMinAffichage: Double = 0.5

    private func consoliderJours() -> [ScoreJournalier] {
        let cal = Calendar.current
        let debutJourCourant = Self.debutJourMetabolique(pour: Date())

        return (1...30).reversed().compactMap { decalage -> ScoreJournalier? in
            guard let debut = cal.date(byAdding: .day, value: -decalage, to: debutJourCourant) else {
                return nil
            }
            let fin = debut.addingTimeInterval(24 * 3600)
            guard let faits = CalculScoreJournalier.faits(
                depuis: echantillons,
                fenetre: debut...fin,
                couvertureMin: Self.couvertureMinAffichage
            ) else {
                return nil
            }
            // Le `ScoreJournalier.jour` est calendaire (00h) — on l'ancre sur le
            // jour calendaire qui *contient* le début métabolique (06h ce jour).
            let jourCalendaire = cal.startOfDay(for: debut)
            return ScoreJournalier(jour: jourCalendaire, faits: faits)
        }
    }

    // MARK: - Accès au hub

    /// Charge les `GlucoseReading` des 31 derniers jours métaboliques (30 jours
    /// consolidés + jour en cours) et les mappe en tuples `(date, valeur)`.
    ///
    /// Le mapping `@Model → tuple` se fait **ici**, côté service, pour que
    /// `CalculScoreJournalier` reste pur et découplé de SwiftData.
    private func chargerEchantillons(contexte: ModelContext) -> [(date: Date, valeur: Int)] {
        let debutJourCourant = Self.debutJourMetabolique(pour: Date())
        let borneBasse = Calendar.current.date(
            byAdding: .day, value: -30, to: debutJourCourant
        ) ?? debutJourCourant

        var descripteur = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= borneBasse },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descripteur.propertiesToFetch = [\.date, \.valeur]

        let lectures = (try? contexte.fetch(descripteur)) ?? []
        return lectures.map { (date: $0.date, valeur: $0.valeur) }
    }

    // MARK: - Faits neutres (jour en cours sans donnée)

    /// `FaitsJour` plancher utilisé quand le jour en cours n'a pas encore de
    /// données exploitables : score 0, tout à zéro. Évite d'inventer une
    /// métrique — la carte montre simplement « 0h de données ».
    private static let faitsNeutres = FaitsJour(
        score: 0,
        tir: 0,
        tbrLevel1: 0,
        tbrLevel2: 0,
        tarLevel1: 0,
        tarLevel2: 0,
        hypoCount: 0,
        severeHypoCount: 0,
        peakTime: nil,
        peakValue: nil,
        mealContext: nil,
        sportContext: nil
    )
}

#if DEBUG
extension ScoreService {

    /// Container in-memory peuplé de ~30 jours de glycémies synthétiques —
    /// alimente le score réel pour les `#Preview`, sans device ni HealthKit.
    @MainActor
    static func conteneurApercu() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: GlucoseReading.self, configurations: config)
        let contexte = container.mainContext
        for lecture in echantillonsApercu() {
            contexte.insert(lecture)
        }
        try? contexte.save()
        return container
    }

    /// ~30 jours de glycémies synthétiques (pas de 5 min, sinusoïde plausible
    /// centrée 130 mg/dL). Couverture suffisante pour que le GRI soit calculé
    /// (≥ 70 %). Uniquement pour previews / captures.
    static func echantillonsApercu() -> [GlucoseReading] {
        let cal = Calendar.current
        let debut = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let pas: TimeInterval = 5 * 60
        let nbPoints = Int(Date().timeIntervalSince(debut) / pas)

        return (0..<nbPoints).map { i in
            let date = debut.addingTimeInterval(Double(i) * pas)
            let phase = Double(i) * pas / (3 * 3600) * 2 * .pi
            let valeur = Int((130 + 45 * sin(phase) + Double((i * 37) % 21 - 10)).rounded())
            return GlucoseReading(date: date, valeur: max(50, min(320, valeur)), source: .manuel)
        }
    }
}
#endif
