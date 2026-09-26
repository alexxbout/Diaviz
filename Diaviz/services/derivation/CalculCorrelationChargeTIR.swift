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

/// Un changement de dose de lente détecté dans la fenêtre — simple repère
/// visuel sur la chronologie, pas la détection de palier complète de B1
/// (`CalculAnalyseBasale`) : ici on ne fait que marquer où la dose a changé.
nonisolated struct MarqueurChangementDose: Sendable, Equatable, Identifiable {
    let date: Date
    let dose: Double
    var id: Date { date }
}

/// Niveau de charge active et TIR moyen des **jours** qui y tombent — même
/// niveau (hystérésis comprise) que partout ailleurs dans l'app. **Pas de
/// seuil minimal d'affichage** — `n` est toujours montré à côté du chiffre,
/// c'est lui qui porte l'honnêteté de la mesure.
nonisolated struct TrancheChargeTIR: Sendable, Equatable, Identifiable {
    let niveau: NiveauChargeActive
    /// `nil` si aucun jour de cette tranche n'a de TIR mesurable.
    let tirMoyen: Double?
    /// Jours du niveau ayant au moins une mesure CGM.
    let nombreJours: Int
    var id: NiveauChargeActive { niveau }
}

/// Dérive basale moyenne (nuit profonde, B1) des nuits dont le **jour**
/// tombe dans ce niveau de charge active. Même garde-fou que
/// `TrancheChargeTIR` : pas de seuil minimal, `n` porte l'honnêteté.
nonisolated struct TrancheDeriveBasale: Sendable, Equatable, Identifiable {
    let niveau: NiveauChargeActive
    /// `nil` si aucune nuit valide (zone 3 analysée) dans cette tranche.
    let deriveMoyenne: Double?
    let nombreNuits: Int
    var id: NiveauChargeActive { niveau }
}

/// Synthèse complète affichée par `PageCorrelationChargeGlycemie`.
nonisolated struct SyntheseCorrelationChargeTIR: Sendable, Equatable {
    /// Chronologique, plus ancienne en premier.
    let semaines: [PointSemaineCorrelation]
    let changementsDose: [MarqueurChangementDose]
    /// Une entrée par niveau, toujours les 3 — `nombreJours` peut être 0.
    let tranches: [TrancheChargeTIR]
    /// Une entrée par niveau — vide si aucune nuit B1 fournie à `analyser`.
    let tranchesDerive: [TrancheDeriveBasale]
}

extension SyntheseCorrelationChargeTIR {
    /// Placeholder avant le premier recalcul (démarrage de l'app) — la carte
    /// sommaire est `.disabled` tant que le vrai `synthese` n'existe pas, ce
    /// `vide` ne sert qu'à donner un `SyntheseCorrelationChargeTIR` non
    /// optionnel à la page poussée si jamais la navigation était forcée.
    static var vide: SyntheseCorrelationChargeTIR {
        SyntheseCorrelationChargeTIR(semaines: [], changementsDose: [], tranches: [], tranchesDerive: [])
    }
}

// MARK: - Calculateur

/// Corrèle, semaine par semaine, la charge active (`ContexteChargeActive`),
/// le temps dans la cible (TIR) et la dérive basale moyenne (B1, nuit
/// profonde), avec les changements de dose de lente comme repères temporels.
/// Purement descriptif — **co-occurrence affichée, jamais une cause
/// affirmée**.
///
/// Les tranches sont faites **par jour**, avec le niveau de charge active de
/// chaque jour : le même que celui des badges et de B2/B3, jamais une
/// deuxième classification propre à cette page.
nonisolated enum CalculCorrelationChargeTIR {

    static let nombreSemaines = 10

    /// - Parameter nuitsDerive: dérive de la nuit profonde `(date de la
    ///   nuit, Δ mg/dL)` — une entrée par nuit **valide** de B1.
    static func analyser(
        charge: ContexteChargeActive,
        glucoses: [(date: Date, valeur: Int)],
        lentes: [(date: Date, dose: Double)],
        nuitsDerive: [(date: Date, derive: Double)] = [],
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

        let debutFenetre = debutsSemaines.first ?? debutSemaineCourante
        let changements = changementsDose(depuis: lentes, fenetre: debutFenetre)

        // TIR par jour, regroupé selon le niveau de charge active du jour.
        var mesuresParJour: [Date: [(date: Date, valeur: Int)]] = [:]
        for g in glucoses where g.date >= debutFenetre && g.date <= maintenant {
            mesuresParJour[calendrier.startOfDay(for: g.date), default: []].append(g)
        }
        let tirsParNiveau: [NiveauChargeActive: [Double]] = mesuresParJour.reduce(into: [:]) { acc, entree in
            guard let niveau = charge.niveau(le: entree.key), let t = tir(entree.value) else { return }
            acc[niveau, default: []].append(t)
        }
        let tranches = NiveauChargeActive.allCases.map { niveau in
            let tirs = tirsParNiveau[niveau] ?? []
            return TrancheChargeTIR(
                niveau: niveau,
                tirMoyen: tirs.isEmpty ? nil : tirs.reduce(0, +) / Double(tirs.count),
                nombreJours: tirs.count
            )
        }

        let tranchesDerive = NiveauChargeActive.allCases.map { niveau in
            let nuits = nuitsDerive.filter { charge.niveau(le: $0.date) == niveau }
            return TrancheDeriveBasale(
                niveau: niveau,
                deriveMoyenne: nuits.isEmpty ? nil : nuits.map(\.derive).reduce(0, +) / Double(nuits.count),
                nombreNuits: nuits.count
            )
        }

        return SyntheseCorrelationChargeTIR(
            semaines: semaines, changementsDose: changements, tranches: tranches, tranchesDerive: tranchesDerive
        )
    }

    private static func tir(_ mesures: [(date: Date, valeur: Int)]) -> Double? {
        guard !mesures.isEmpty else { return nil }
        return Double(mesures.filter { (70...180).contains($0.valeur) }.count) / Double(mesures.count) * 100
    }

    /// Score = 100 − GRI (Klonoff 2022), même formule et mêmes coefficients
    /// que la carte accueil (`CalculScoreJournalier`) — dupliqués ici plutôt
    /// que réutilisés car ce calculateur-ci l'applique sur une semaine entière
    /// de lectures d'un coup, pas jour par jour avec un seuil de couverture.
    private static func scoreGRI(mesures: [(date: Date, valeur: Int)]) -> Double? {
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

    /// Un marqueur par changement de valeur de dose, en ordre chronologique
    /// — regroupement simple, pas la détection de palier complète de B1.
    private static func changementsDose(
        depuis lentes: [(date: Date, dose: Double)], fenetre debut: Date
    ) -> [MarqueurChangementDose] {
        let triees = lentes.filter { $0.date >= debut }.sorted { $0.date < $1.date }
        var marqueurs: [MarqueurChangementDose] = []
        var doseCourante: Double?
        for lente in triees {
            if doseCourante == nil {
                doseCourante = lente.dose
                continue
            }
            if lente.dose != doseCourante {
                marqueurs.append(MarqueurChangementDose(date: lente.date, dose: lente.dose))
                doseCourante = lente.dose
            }
        }
        return marqueurs
    }

    private static func debutDeSemaine(_ date: Date, calendrier: Calendar) -> Date {
        var cal = calendrier
        cal.firstWeekday = 2 // lundi
        let composants = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: composants) ?? calendrier.startOfDay(for: date)
    }
}
