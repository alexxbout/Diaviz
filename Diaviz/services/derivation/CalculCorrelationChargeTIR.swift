//
//  CalculCorrelationChargeTIR.swift
//  diaviz
//

import Foundation

// MARK: - Résultat

/// Une semaine de la série — charge (score continu) et TIR, tous deux
/// **toujours peuplés** (0/`nil` si rien à mesurer), jamais de trou
/// silencieux dans la chronologie affichée.
nonisolated struct PointSemaineCorrelation: Sendable, Equatable, Identifiable {
    let debutSemaine: Date
    let charge: Double
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

/// Tranche de charge (basse/normale/haute vs normale perso) et le TIR moyen
/// des semaines qui y tombent. **Pas de seuil minimal d'affichage** — `n`
/// est toujours montré à côté du chiffre, c'est lui qui porte l'honnêteté
/// de la mesure, pas un gate qui cacherait la tranche.
nonisolated struct TrancheChargeTIR: Sendable, Equatable, Identifiable {
    let niveau: NiveauChargeCorrelation
    /// `nil` si aucune semaine de cette tranche n'a de TIR mesurable.
    let tirMoyen: Double?
    let nombreSemaines: Int
    var id: NiveauChargeCorrelation { niveau }
}

nonisolated enum NiveauChargeCorrelation: Sendable, CaseIterable {
    case basse, normale, haute

    var libelle: String {
        switch self {
        case .basse:    return "Charge basse"
        case .normale:  return "Charge normale"
        case .haute:    return "Charge haute"
        }
    }
}

/// Dérive basale moyenne (nuit profonde, B1) des nuits dont la **semaine**
/// tombe dans cette tranche de charge. Même garde-fou que `TrancheChargeTIR` :
/// pas de seuil minimal, `n` (en nuits, pas en semaines) porte l'honnêteté.
nonisolated struct TrancheDeriveBasale: Sendable, Equatable, Identifiable {
    let niveau: NiveauChargeCorrelation
    /// `nil` si aucune nuit valide (zone 3 analysée) dans cette tranche.
    let deriveMoyenne: Double?
    let nombreNuits: Int
    var id: NiveauChargeCorrelation { niveau }
}

/// Synthèse complète affichée par `PageCorrelationChargeGlycemie`.
nonisolated struct SyntheseCorrelationChargeTIR: Sendable, Equatable {
    /// Chronologique, plus ancienne en premier.
    let semaines: [PointSemaineCorrelation]
    let changementsDose: [MarqueurChangementDose]
    /// Une entrée par niveau, toujours les 3 — `nombreSemaines` peut être 0.
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

/// Corrèle, semaine par semaine, la charge d'activité continue
/// (`CalculChargeContinue`), le temps dans la cible (TIR) et la dérive
/// basale moyenne (B1, nuit profonde), avec les changements de dose de
/// lente comme repères temporels. Purement descriptif — **co-occurrence
/// affichée, jamais une cause affirmée** (même garde-fou que B2/B3 pour
/// sport/glucides).
///
/// Les nuits B1 sont fournies par l'appelant (`nuitsDerive`), calculées en
/// faisant tourner `CalculAnalyseBasale` sur l'horizon complet de cette page
/// (`fenetreNuits` élargie à `nombreSemaines * 7`) plutôt que sa fenêtre 14
/// nuits habituelle — ce calculateur-ci ne connaît rien à B1, il ne fait que
/// regrouper des dérives déjà calculées par semaine de charge.
nonisolated enum CalculCorrelationChargeTIR {

    static let nombreSemaines = 10

    /// - Parameter nuitsDerive: dérive de la nuit profonde `(date de la
    ///   nuit, Δ mg/dL)` — une entrée par nuit **valide** de B1 (zone 3
    ///   analysée). Vide par défaut : `tranchesDerive` sort alors à 0 partout,
    ///   dégradation gracieuse pour les appelants qui n'ont pas encore
    ///   branché B1 sur cette fenêtre élargie.
    static func analyser(
        activites: [(debut: Date, dureeMin: Int, intensite: IntensiteSport)],
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
            let charge = activites
                .filter { $0.debut >= debut && $0.debut < fin }
                .reduce(0.0) { $0 + Double($1.dureeMin) * CalculChargeContinue.facteur($1.intensite) }
            let mesures = glucoses.filter { $0.date >= debut && $0.date < fin }
            let tir: Double? = mesures.isEmpty ? nil : Double(
                mesures.filter { (70...180).contains($0.valeur) }.count
            ) / Double(mesures.count) * 100
            let score = scoreGRI(mesures: mesures)
            return PointSemaineCorrelation(debutSemaine: debut, charge: charge, tir: tir, score: score)
        }

        let debutFenetre = debutsSemaines.first ?? debutSemaineCourante
        let changements = changementsDose(depuis: lentes, fenetre: debutFenetre)

        let moyenneCharge = semaines.map(\.charge).reduce(0, +) / Double(max(semaines.count, 1))
        // Niveau par semaine, calculé une fois — réutilisé pour le TIR (par
        // semaine) et la dérive basale (par nuit, via la semaine qui la contient).
        let niveauParSemaine: [Date: NiveauChargeCorrelation] = Dictionary(
            uniqueKeysWithValues: semaines.map { ($0.debutSemaine, tranche(pour: $0.charge, moyenne: moyenneCharge)) }
        )

        let tranches = NiveauChargeCorrelation.allCases.map { niveau in
            let semainesTranche = semaines.filter { niveauParSemaine[$0.debutSemaine] == niveau }
            let tirsMesures = semainesTranche.compactMap(\.tir)
            let tirMoyen = tirsMesures.isEmpty ? nil : tirsMesures.reduce(0, +) / Double(tirsMesures.count)
            return TrancheChargeTIR(niveau: niveau, tirMoyen: tirMoyen, nombreSemaines: semainesTranche.count)
        }

        let tranchesDerive = tranchesDerive(
            nuitsDerive: nuitsDerive, niveauParSemaine: niveauParSemaine, calendrier: calendrier
        )

        return SyntheseCorrelationChargeTIR(
            semaines: semaines, changementsDose: changements, tranches: tranches, tranchesDerive: tranchesDerive
        )
    }

    /// Regroupe chaque nuit B1 par le niveau de charge de **la semaine qui
    /// la contient** (même semaines lundi-dimanche que le reste du calcul).
    private static func tranchesDerive(
        nuitsDerive: [(date: Date, derive: Double)],
        niveauParSemaine: [Date: NiveauChargeCorrelation],
        calendrier: Calendar
    ) -> [TrancheDeriveBasale] {
        NiveauChargeCorrelation.allCases.map { niveau in
            let nuitsTranche = nuitsDerive.filter { nuit in
                niveauParSemaine[debutDeSemaine(nuit.date, calendrier: calendrier)] == niveau
            }
            let deriveMoyenne = nuitsTranche.isEmpty
                ? nil
                : nuitsTranche.map(\.derive).reduce(0, +) / Double(nuitsTranche.count)
            return TrancheDeriveBasale(niveau: niveau, deriveMoyenne: deriveMoyenne, nombreNuits: nuitsTranche.count)
        }
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

    private static func tranche(pour charge: Double, moyenne: Double) -> NiveauChargeCorrelation {
        guard moyenne > 0 else { return .normale }
        let ecart = (charge - moyenne) / moyenne
        if ecart <= -CalculChargeContinue.seuilEcartTendance { return .basse }
        if ecart >= CalculChargeContinue.seuilEcartTendance { return .haute }
        return .normale
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
