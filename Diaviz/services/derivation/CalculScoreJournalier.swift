//
//  CalculScoreJournalier.swift
//  diaviz
//
//  Created by Alexandre on 20/06/2026.
//

import Foundation

/// Assembleur **pur** du score quotidien (GRI, Klonoff 2022).
///
/// `enum` sans cas + `nonisolated static func` : aucune dépendance au
/// `@Model GlucoseReading`, aucune isolation d'acteur, aucune entrée/sortie.
/// Le service (`ScoreService`) mappe les `GlucoseReading` du hub en tuples
/// `(date, valeur)` *avant* d'appeler ce calcul, afin que la logique reste
/// testable, `Sendable` et réutilisable hors contexte SwiftData.
///
/// Convention « un hub, des dérivations » : rien n'est persisté ici, tout est
/// recalculé à la volée depuis les échantillons CGM bruts.
///
/// `nonisolated` sur le type : le projet a `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, donc sans ce marquage chaque constante/méthode serait
/// implicitement MainActor-isolée — inutilisable depuis `faits(...)`,
/// lui-même `nonisolated`.
nonisolated enum CalculScoreJournalier {

    // MARK: - Constantes GRI / couverture

    /// Coefficients GRI par zone hors-cible (Klonoff 2022).
    private static let coeffTBR2: Double = 3.0   // < 54 mg/dL
    private static let coeffTBR1: Double = 2.4   // 54–69 mg/dL
    private static let coeffTAR2: Double = 1.6   // > 250 mg/dL
    private static let coeffTAR1: Double = 0.8   // 181–250 mg/dL

    /// Cadence nominale d'un CGM : un échantillon toutes les 5 minutes.
    static let intervalleEchantillonSec: TimeInterval = 5 * 60

    /// Seuil d'hypoglycémie (mg/dL) — un épisode commence sous ce seuil et se
    /// clôt au retour ≥ 70.
    private static let seuilHypo = 70
    /// Seuil d'hypoglycémie sévère (mg/dL).
    private static let seuilHypoSevere = 54

    // MARK: - Calcul principal

    /// Assemble le `FaitsJour` d'une fenêtre temporelle à partir d'échantillons
    /// CGM bruts, ou `nil` si la couverture est insuffisante (dégradation
    /// gracieuse — on préfère ne rien afficher plutôt qu'un score faussé).
    ///
    /// - Parameters:
    ///   - lectures: échantillons `(date, valeur mg/dL)`, ordre indifférent.
    ///   - fenetre: borne `[début, fin]` du jour métabolique évalué. Pour un
    ///     jour terminé, `fin = début + 24h` ; pour le jour en cours,
    ///     `fin = maintenant` (couverture attendue réduite d'autant).
    ///   - couvertureMin: fraction minimale d'échantillons attendus pour
    ///     produire un score (0.70 = 70 %).
    /// - Returns: `FaitsJour` complet, ou `nil` si couverture < `couvertureMin`
    ///   ou fenêtre vide.
    nonisolated static func faits(
        depuis lectures: [(date: Date, valeur: Int)],
        fenetre: ClosedRange<Date>,
        couvertureMin: Double = 0.70
    ) -> FaitsJour? {
        // Échantillons effectivement dans la fenêtre, triés chronologiquement.
        let dansFenetre = lectures
            .filter { fenetre.contains($0.date) }
            .sorted { $0.date < $1.date }

        guard !dansFenetre.isEmpty else { return nil }

        // Couverture = présents / attendus. Attendus = durée de la fenêtre / 5 min.
        let dureeFenetre = fenetre.upperBound.timeIntervalSince(fenetre.lowerBound)
        let attendus = max(1.0, dureeFenetre / intervalleEchantillonSec)
        let couverture = Double(dansFenetre.count) / attendus
        guard couverture >= couvertureMin else { return nil }

        let total = Double(dansFenetre.count)
        let valeurs = dansFenetre.map(\.valeur)

        // Répartition par bande (fractions du total, en %).
        var nbTBR2 = 0, nbTBR1 = 0, nbTIR = 0, nbTAR1 = 0, nbTAR2 = 0
        for valeur in valeurs {
            switch valeur {
            case ..<54:     nbTBR2 += 1
            case 54...69:   nbTBR1 += 1
            case 70...180:  nbTIR += 1
            case 181...250: nbTAR1 += 1
            default:        nbTAR2 += 1   // > 250
            }
        }

        let pctTBR2 = Double(nbTBR2) / total * 100
        let pctTBR1 = Double(nbTBR1) / total * 100
        let pctTIR = Double(nbTIR) / total * 100
        let pctTAR1 = Double(nbTAR1) / total * 100
        let pctTAR2 = Double(nbTAR2) / total * 100

        // GRI (Klonoff 2022) puis score = 100 − GRI, borné [0, 100].
        let gri = coeffTBR2 * pctTBR2
            + coeffTBR1 * pctTBR1
            + coeffTAR2 * pctTAR2
            + coeffTAR1 * pctTAR1
        let score = max(0, min(100, Int((100 - gri).rounded())))

        // Épisodes d'hypo distincts (séparés par un retour ≥ 70).
        let (hypoCount, severeHypoCount) = comptageHypos(valeurs)

        // Pic : plus haute valeur de la fenêtre + son horodatage en "HH:mm".
        let (peakTime, peakValue) = pic(dansFenetre)

        return FaitsJour(
            score: score,
            tir: pctTIR,
            tbrLevel1: pctTBR1,
            tbrLevel2: pctTBR2,
            tarLevel1: pctTAR1,
            tarLevel2: pctTAR2,
            hypoCount: hypoCount,
            severeHypoCount: severeHypoCount,
            peakTime: peakTime,
            peakValue: peakValue,
            mealContext: nil,
            sportContext: nil
        )
    }

    // MARK: - Sous-calculs

    /// Compte les épisodes d'hypoglycémie distincts. Un épisode débute au
    /// premier point < 70 et se clôt au retour ≥ 70 ; un nouvel épisode requiert
    /// donc un retour en cible préalable. `severe` = épisode atteignant < 54.
    /// `nonisolated` + public : réutilisé par les métriques d'accueil (carte
    /// Hypos) sans le seuil de couverture du score.
    nonisolated static func comptageHypos(_ valeurs: [Int]) -> (hypo: Int, severe: Int) {
        var hypo = 0
        var severe = 0
        var enEpisode = false
        var episodeSevere = false

        for valeur in valeurs {
            if valeur < seuilHypo {
                if !enEpisode {
                    enEpisode = true
                    episodeSevere = false
                    hypo += 1
                }
                if valeur < seuilHypoSevere, !episodeSevere {
                    episodeSevere = true
                    severe += 1
                }
            } else {
                enEpisode = false
                episodeSevere = false
            }
        }
        return (hypo, severe)
    }

    /// Valeur maximale de la fenêtre et son heure formatée `HH:mm` (locale
    /// courante). `nil` si aucun échantillon (déjà garanti non-vide en amont,
    /// mais on reste défensif).
    private static func pic(_ lectures: [(date: Date, valeur: Int)]) -> (heure: String?, valeur: Int?) {
        guard let sommet = lectures.max(by: { $0.valeur < $1.valeur }) else {
            return (nil, nil)
        }
        let formateur = DateFormatter()
        formateur.locale = .current
        formateur.dateFormat = "HH:mm"
        return (formateur.string(from: sommet.date), sommet.valeur)
    }
}
