//
//  CalculCorrelationChargeTIR.swift
//  diaviz
//

import Foundation

// MARK: - Résultat

/// Une semaine de la série — charge active relative et TIR, jamais de trou
/// silencieux dans la chronologie affichée (`nil` si rien à mesurer).
nonisolated struct PointSemaineCorrelation: Sendable, Equatable, Identifiable {
    let debutSemaine: Date
    /// Moyenne du stock de charge active sur la semaine / normale personnelle
    /// (1 = habituel). `nil` sans assez de recul. Jamais le nombre brut.
    let indiceCharge: Double?
    /// `nil` si aucune `GlucoseReading` sur la semaine (capteur absent).
    let tir: Double?
    /// Score quotidien moyen (100 − GRI, Klonoff 2022) sur la semaine — même
    /// formule que la carte accueil, recalculée directement sur les lectures
    /// de la semaine plutôt que moyennée jour par jour. `nil` si aucune
    /// lecture (même condition que `tir`).
    let score: Double?
    var id: Date { debutSemaine }
}

/// Synthèse complète affichée par `PageCorrelationChargeGlycemie`.
nonisolated struct SyntheseCorrelationChargeTIR: Sendable, Equatable {
    /// Chronologique, plus ancienne en premier.
    let semaines: [PointSemaineCorrelation]
}

nonisolated extension SyntheseCorrelationChargeTIR {
    /// Placeholder avant le premier recalcul (démarrage de l'app) — la carte
    /// sommaire est `.disabled` tant que le vrai `synthese` n'existe pas, ce
    /// `vide` ne sert qu'à donner un `SyntheseCorrelationChargeTIR` non
    /// optionnel à la page poussée si jamais la navigation était forcée.
    static var vide: SyntheseCorrelationChargeTIR {
        SyntheseCorrelationChargeTIR(semaines: [])
    }
}

// MARK: - Calculateur

/// Chronologie de la page « Charge et glycémie » : semaine par semaine, la
/// charge active (`ContexteChargeActive`) rapportée à la référence, le
/// score GRI et le temps dans la cible. Purement descriptif —
/// **co-occurrence affichée, jamais une cause affirmée**.
nonisolated enum CalculCorrelationChargeTIR {

    static let nombreSemaines = 10

    static func analyser(
        charge: ContexteChargeActive,
        glucoses: [(date: Date, valeur: Int)],
        maintenant: Date = Date(),
        calendrier: Calendar = .current
    ) -> SyntheseCorrelationChargeTIR {
        let debutSemaineCourante = debutDeSemaine(maintenant, calendrier: calendrier)
        let debutsSemaines: [Date] = (0..<nombreSemaines).compactMap {
            calendrier.date(byAdding: .day, value: -7 * (nombreSemaines - 1 - $0), to: debutSemaineCourante)
        }

        let semaines = debutsSemaines.map { debut -> PointSemaineCorrelation in
            let fin = calendrier.date(byAdding: .day, value: 7, to: debut) ?? debut
            let mesures = glucoses.filter { $0.date >= debut && $0.date < fin }
            return PointSemaineCorrelation(
                debutSemaine: debut,
                indiceCharge: charge.indiceMoyen(de: debut, a: min(fin, maintenant)),
                tir: tir(mesures),
                score: scoreGRI(mesures: mesures)
            )
        }
        return SyntheseCorrelationChargeTIR(semaines: semaines)
    }

    static func tir(_ mesures: [(date: Date, valeur: Int)]) -> Double? {
        guard !mesures.isEmpty else { return nil }
        return Double(mesures.filter { (70...180).contains($0.valeur) }.count) / Double(mesures.count) * 100
    }

    /// Score = 100 − GRI (Klonoff 2022), même formule et mêmes coefficients
    /// que la carte accueil (`CalculScoreJournalier`) — dupliqués ici plutôt
    /// que réutilisés car ce calculateur-ci l'applique sur une semaine entière
    /// de lectures d'un coup, pas jour par jour avec un seuil de couverture.
    static func scoreGRI(mesures: [(date: Date, valeur: Int)]) -> Double? {
        guard !mesures.isEmpty else { return nil }
        let total = Double(mesures.count)
        let pct = { (plage: (Int) -> Bool) in
            Double(mesures.filter { plage($0.valeur) }.count) / total * 100
        }
        let gri = 3.0 * pct { $0 < 54 }
            + 2.4 * pct { (54...69).contains($0) }
            + 1.6 * pct { $0 > 250 }
            + 0.8 * pct { (181...250).contains($0) }
        return max(0, min(100, 100 - gri))
    }

    private static func debutDeSemaine(_ date: Date, calendrier: Calendar) -> Date {
        var cal = calendrier
        cal.firstWeekday = 2 // lundi
        let composants = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: composants) ?? calendrier.startOfDay(for: date)
    }
}
