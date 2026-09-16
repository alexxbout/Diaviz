//
//  CalculChargeContinue.swift
//  diaviz
//

import Foundation

// MARK: - Résultat

/// Score de charge d'un jour calendaire — `duréeMinutes × facteur intensité`,
/// sommé sur toutes les séances du jour. Toujours peuplé (0 si repos), jamais
/// de trou silencieux dans la série.
nonisolated struct PointChargeJour: Sendable, Equatable, Hashable, Identifiable {
    let jour: Date
    let score: Double
    var id: Date { jour }
}

/// Sens d'évolution de la charge, sur au moins `CalculChargeContinue.joursMinimumTendance`
/// jours consécutifs d'écart marqué avec la normale — évite de signaler une
/// « tendance » dès le premier jour de repos.
nonisolated enum TendanceChargeActivite: Sendable, Equatable {
    case enHausse(jours: Int)
    case enBaisse(jours: Int)
    case stable
}

/// Synthèse de charge continue sur fenêtre glissante.
nonisolated struct SyntheseChargeContinue: Sendable, Equatable {
    /// 14 derniers jours, du plus ancien au plus récent (aujourd'hui inclus).
    let serieJournaliere: [PointChargeJour]
    /// Somme des 7 derniers jours (charge « cette semaine »).
    let chargeSemaine: Double
    /// Moyenne hebdomadaire glissante sur les 4 dernières semaines pleines —
    /// la **normale personnelle**, pas une norme externe.
    let normaleHebdo: Double
    /// `(chargeSemaine - normaleHebdo) / normaleHebdo`, borné à [-1, +∞).
    /// `nil` si `normaleHebdo` est nulle (aucune activité sur 4 semaines —
    /// un écart n'a pas de sens sans référence).
    let ecartRelatif: Double?
    let tendance: TendanceChargeActivite
}

// MARK: - Calculateur

/// Charge d'activité **continue** — remplace la lecture par paliers de
/// `CalculChargeActivite` (0/1-2/3-4/5+ séances) pour tout usage qui a besoin
/// d'une granularité fine (graphique, comparaison à une normale). Purement
/// descriptif, sans dépendance au hub.
///
/// Score journalier = Σ (durée × facteur intensité) des séances du jour.
/// Facteurs choisis pour qu'une séance intense pèse nettement plus qu'une
/// séance faible à durée égale (littérature : `session-RPE` de Foster —
/// durée × intensité ressentie comme proxy de charge d'entraînement),
/// sans viser une unité physiologique précise (journal personnel, pas un
/// laboratoire).
nonisolated enum CalculChargeContinue {

    /// Nombre de jours d'écart marqué requis avant d'afficher une tendance —
    /// un seul jour de repos ne change rien, 3 jours de suite si.
    static let joursMinimumTendance = 3
    /// Écart relatif (vs normale) à partir duquel un jour compte comme
    /// « marqué » pour la détection de tendance.
    static let seuilEcartTendance = 0.4

    static func facteur(_ intensite: IntensiteSport) -> Double {
        switch intensite {
        case .faible:   1.0
        case .moderee:  2.0
        case .intense:  3.0
        }
    }

    /// - Parameter activites: séances `(début, durée, intensité)` sur au
    ///   moins 35 jours pour que la normale (4 semaines) ait un sens.
    static func analyser(
        activites: [(debut: Date, dureeMin: Int, intensite: IntensiteSport)],
        maintenant: Date = Date(),
        calendrier: Calendar = .current
    ) -> SyntheseChargeContinue {
        let aujourdhui = calendrier.startOfDay(for: maintenant)

        var scoreParJour: [Date: Double] = [:]
        for a in activites {
            let jour = calendrier.startOfDay(for: a.debut)
            scoreParJour[jour, default: 0] += Double(a.dureeMin) * facteur(a.intensite)
        }

        // Série affichée : 14 jours.
        let jours14: [Date] = (0..<14).compactMap {
            calendrier.date(byAdding: .day, value: -(13 - $0), to: aujourdhui)
        }
        let serie = jours14.map { PointChargeJour(jour: $0, score: scoreParJour[$0] ?? 0) }

        let chargeSemaine = sommeFenetre(0, calendrier: calendrier, aujourdhui: aujourdhui, scores: scoreParJour)

        // Normale = moyenne des 4 semaines glissantes précédant la semaine
        // courante (S-1 à S-4), pas la semaine en cours elle-même.
        let semaines = (1...4).map { decalage in
            sommeFenetre(decalage * 7, calendrier: calendrier, aujourdhui: aujourdhui, scores: scoreParJour)
        }
        let normale = semaines.reduce(0, +) / Double(semaines.count)

        let ecart: Double? = normale > 0 ? max(-1, (chargeSemaine - normale) / normale) : nil

        let tendance = tendanceDepuisSerie(
            jours14: jours14, scores: scoreParJour, normaleJournaliere: normale / 7
        )

        return SyntheseChargeContinue(
            serieJournaliere: serie,
            chargeSemaine: chargeSemaine,
            normaleHebdo: normale,
            ecartRelatif: ecart,
            tendance: tendance
        )
    }

    /// Somme des scores sur les 7 jours se terminant `decalageJours` jours
    /// avant aujourd'hui (0 = semaine courante, 7 = semaine précédente…).
    private static func sommeFenetre(
        _ decalageJours: Int, calendrier: Calendar, aujourdhui: Date, scores: [Date: Double]
    ) -> Double {
        (0..<7).reduce(0.0) { total, offset in
            guard let jour = calendrier.date(byAdding: .day, value: -(decalageJours + offset), to: aujourdhui)
            else { return total }
            return total + (scores[jour] ?? 0)
        }
    }

    /// Tendance : compte, en partant d'aujourd'hui, les jours consécutifs
    /// dont le score journalier dévie de plus de `seuilEcartTendance` par
    /// rapport à `normaleJournaliere`, dans le même sens.
    private static func tendanceDepuisSerie(
        jours14: [Date], scores: [Date: Double], normaleJournaliere: Double
    ) -> TendanceChargeActivite {
        guard normaleJournaliere > 0 else { return .stable }
        var joursBaisse = 0
        var joursHausse = 0
        for jour in jours14.reversed() {
            let score = scores[jour] ?? 0
            let ecart = (score - normaleJournaliere) / normaleJournaliere
            if ecart <= -seuilEcartTendance {
                if joursHausse > 0 { break }
                joursBaisse += 1
            } else if ecart >= seuilEcartTendance {
                if joursBaisse > 0 { break }
                joursHausse += 1
            } else {
                break
            }
        }
        if joursBaisse >= joursMinimumTendance { return .enBaisse(jours: joursBaisse) }
        if joursHausse >= joursMinimumTendance { return .enHausse(jours: joursHausse) }
        return .stable
    }
}
