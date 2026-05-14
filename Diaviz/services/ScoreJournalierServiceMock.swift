//
//  ScoreJournalierServiceMock.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import Foundation
import Observation

// MARK: - Modèle

/// Score quotidien complet — agrège le `FaitsJour` (qui contient déjà
/// la décomposition GRI via `tbrLevel1/2`, `tarLevel1/2`, `tir`) et
/// expose des helpers de durée (en secondes) pour les rows de
/// décomposition.
///
/// Note : les pourcentages sont la source de vérité ; les durées sont
/// dérivées (24h × %) pour l'affichage.
struct ScoreJournalier: Sendable, Equatable, Hashable {
    /// Jour calendaire (00:00 local) auquel ce score se rapporte.
    let jour: Date

    /// Faits du jour — contient le score et toutes les métriques GRI.
    let faits: FaitsJour

    /// Score 0–100 — convenience.
    var score: Int { faits.score }

    /// Durée totale d'une journée standardisée (24h) — base des
    /// conversions pourcentage → durée. Le mock raisonne en journée
    /// pleine ; le vrai service utilisera la couverture CGM réelle.
    static let dureeJourSec: TimeInterval = 24 * 60 * 60

    /// Convertit un pourcentage (0–100) en durée (secondes).
    static func duree(pourPourcent pct: Double) -> TimeInterval {
        max(0, pct) / 100.0 * dureeJourSec
    }
}

// MARK: - Service

/// Service mocké pour la page de détail du score de gestion.
///
/// Expose 30 jours de scores quotidiens, du plus ancien (J-30) à
/// hier (J-1). Le jour courant (aujourd'hui) n'est jamais inclus :
/// le score se calcule a posteriori, on attend la fin de la journée.
///
/// Les décompositions GRI sont générées algorithmiquement à partir du
/// score cible — chaque jour est plausible et déterministe (même
/// `jitter` → même répartition).
@Observable
@MainActor
final class ScoreJournalierServiceMock {

    static let shared = ScoreJournalierServiceMock()

    /// Tous les scores connus, du plus ancien au plus récent.
    private(set) var scores: [ScoreJournalier]

    private init() {
        self.scores = Self.donneesInitiales()
    }

    // MARK: Lecture

    /// Score pour un jour donné (`isDate(:inSameDayAs:)`), ou `nil`
    /// si non couvert par les 30 derniers jours.
    func score(pour jour: Date) -> ScoreJournalier? {
        let cal = Calendar.current
        return scores.first { cal.isDate($0.jour, inSameDayAs: jour) }
    }

    /// 7 jours menant jusqu'au jour donné inclus, du plus ancien (J-6)
    /// au plus récent (jour). Les jours sans donnée (hors plage)
    /// retournent `nil` — la bar chart les rend en barres atténuées.
    func historiqueSept(jusquA jour: Date) -> [(jour: Date, score: Int?)] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: jour)
        return (0..<7).reversed().compactMap { decalage in
            guard let j = cal.date(byAdding: .day, value: -decalage, to: base) else {
                return nil
            }
            return (j, score(pour: j)?.score)
        }
    }

    /// Plage navigable : 30 derniers jours, du plus ancien (J-30) à
    /// hier (J-1). Aujourd'hui exclu (pas de score consolidé).
    var joursNavigables: [Date] {
        scores.map(\.jour).sorted()
    }

    // MARK: Génération mockée

    /// 30 jours de scores variés, de J-30 (plus ancien) à J-1 (hier).
    /// Tableau de scores plausibles enchaînant bonnes / moyennes /
    /// difficiles journées — donne du grain à voir en navigation.
    private static func donneesInitiales() -> [ScoreJournalier] {
        let cal = Calendar.current
        let aujourdhui = cal.startOfDay(for: Date())

        // 30 scores du plus ancien (index 0 = J-30) au plus récent
        // (index 29 = J-1). Variations volontaires pour exercer tous
        // les paliers qualitatifs.
        let scoresParJour: [Int] = [
            68, 75, 82, 71, 58, 64, 79,   // J-30 à J-24
            88, 84, 76, 65, 51, 73, 80,   // J-23 à J-17
            85, 92, 78, 69, 41, 55, 71,   // J-16 à J-10
            83, 76, 88, 67, 52, 74, 81,   // J-9 à J-3
            78, 82,                         // J-2, J-1 (hier)
        ]

        return scoresParJour.enumerated().compactMap { (index, score) -> ScoreJournalier? in
            let decalage = 30 - index
            guard let jour = cal.date(byAdding: .day, value: -decalage, to: aujourdhui) else {
                return nil
            }
            return ScoreJournalier(
                jour: jour,
                faits: faits(pourScore: score, jitter: index)
            )
        }
    }

    /// Reconstruit un `FaitsJour` plausible à partir d'un score cible.
    ///
    /// On part de l'identité GRI = 100 − score, puis on alloue le
    /// budget GRI entre les 4 zones hors-cible selon des ratios fixes,
    /// avec un léger jitter déterministe (basé sur `jitter`) pour que
    /// deux journées de même score n'aient pas exactement la même
    /// répartition.
    ///
    /// Coefficients GRI (Klonoff 2022) :
    ///   - tbrLevel2 (< 54)   × 3.0
    ///   - tbrLevel1 (54–69)  × 2.4
    ///   - tarLevel2 (> 250)  × 1.6
    ///   - tarLevel1 (181–250) × 0.8
    ///
    /// Allocation par défaut : 30 % du budget en hypo, 70 % en hyper —
    /// reflète un profil typique de diabétique de type 1 sous
    /// schéma basal-bolus (plus d'hypers post-prandiaux que d'hypos).
    private static func faits(pourScore score: Int, jitter: Int) -> FaitsJour {
        let gri = Double(max(0, min(100, 100 - score)))

        // Jitter déterministe sur la part hypo / hyper (-0.08 à +0.08).
        let bruit = Double((jitter * 17) % 11 - 5) / 60.0
        let partHypo = 0.30 + bruit

        // Hypo : 70 % du budget hypo va sur niveau 1 (54–69), 30 % sur
        // niveau 2 (< 54, sévère). Division par le coefficient GRI
        // pour retrouver le pourcentage.
        let budgetHypo = gri * partHypo
        let tbrLevel1 = (budgetHypo * 0.7) / 2.4
        let tbrLevel2 = (budgetHypo * 0.3) / 3.0

        // Hyper : 80 % sur niveau 1 (181–250), 20 % sur niveau 2 (> 250).
        let budgetHyper = gri * (1 - partHypo)
        let tarLevel1 = (budgetHyper * 0.8) / 0.8
        let tarLevel2 = (budgetHyper * 0.2) / 1.6

        let tir = max(0, 100 - tbrLevel1 - tbrLevel2 - tarLevel1 - tarLevel2)

        let hypoCount = Int((tbrLevel1 * 0.8 + tbrLevel2 * 1.2).rounded())
        let severeHypoCount = tbrLevel2 > 0.5 ? max(1, Int(tbrLevel2.rounded())) : 0

        let peakValue: Int = {
            if tarLevel2 > 2 { return 285 }
            if tarLevel2 > 0.5 { return 258 }
            if tarLevel1 > 15 { return 232 }
            if tarLevel1 > 5 { return 205 }
            return 188
        }()

        return FaitsJour(
            score: score,
            tir: tir,
            tbrLevel1: tbrLevel1,
            tbrLevel2: tbrLevel2,
            tarLevel1: tarLevel1,
            tarLevel2: tarLevel2,
            hypoCount: hypoCount,
            severeHypoCount: severeHypoCount,
            peakTime: heuresPicMock(jitter: jitter),
            peakValue: peakValue,
            mealContext: nil,
            sportContext: nil
        )
    }

    /// Heure de pic mockée — tourne entre quelques créneaux plausibles
    /// (déjeuner, dîner, milieu d'après-midi) selon `jitter`.
    private static func heuresPicMock(jitter: Int) -> String {
        let creneaux = ["13:30", "14:15", "20:00", "21:30", "16:45"]
        return creneaux[abs(jitter) % creneaux.count]
    }
}
