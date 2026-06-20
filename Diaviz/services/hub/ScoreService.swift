//
//  ScoreService.swift
//  diaviz
//
//  Created by Alexandre on 20/06/2026.
//

import Foundation
import Observation
import SwiftData

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
        let aujourdhui = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { decalage in
            guard let j = cal.date(byAdding: .day, value: -decalage, to: base) else {
                return nil
            }
            if cal.isDate(j, inSameDayAs: aujourdhui) {
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
    static func debutJourMetabolique(pour date: Date = Date()) -> Date {
        let cal = Calendar.current
        let sixHeures = cal.date(
            bySettingHour: 6, minute: 0, second: 0, of: date
        ) ?? date
        if date < sixHeures {
            return cal.date(byAdding: .day, value: -1, to: sixHeures) ?? sixHeures
        }
        return sixHeures
    }

    /// Heures écoulées depuis le début du jour métabolique courant, bornées
    /// [0, 24].
    var heuresDataDuJour: Double {
        let now = Date()
        let debut = Self.debutJourMetabolique(pour: now)
        return max(0, min(24, now.timeIntervalSince(debut) / 3600))
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

    /// `ScoreJournalier` partiel d'aujourd'hui — fenêtre du jour métabolique
    /// courant tronquée à l'instant présent. Couverture attendue réduite à la
    /// durée écoulée (pas 24h), pour ne pas pénaliser une journée qui commence.
    /// Retombe sur des `FaitsJour` neutres si la couverture est insuffisante.
    var partielDuJour: ScoreJournalier {
        let cal = Calendar.current
        let aujourdhui = cal.startOfDay(for: Date())
        let now = Date()
        let debut = Self.debutJourMetabolique(pour: now)
        let fenetre = debut...max(debut, now)
        let faits = CalculScoreJournalier.faits(depuis: echantillons, fenetre: fenetre)
            ?? Self.faitsNeutres
        return ScoreJournalier(jour: aujourdhui, faits: faits)
    }

    // MARK: - Consolidation des jours terminés

    /// Reconstruit les scores des 30 jours métaboliques **terminés** précédant
    /// aujourd'hui (J-30 … J-1). Un jour sans couverture suffisante est omis
    /// (dégradation gracieuse) — il apparaîtra en barre atténuée côté carte.
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
                fenetre: debut...fin
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
