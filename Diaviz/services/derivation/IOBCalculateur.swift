//
//  IOBCalculateur.swift
//  diaviz
//

import Foundation

/// Injection rapide minimale pour le calcul d'IOB — on ne retient que l'instant
/// et la dose. Type valeur `Sendable` : le calcul peut tourner hors `MainActor`
/// (ex. entraînement ML la nuit).
struct InjectionPourIOB: Sendable, Equatable {
    let heure: Date
    let dose: Double
}

/// Point de la courbe de décroissance IOB projetée. Exprimé en minutes depuis
/// « maintenant » (0 = instant courant, positif = futur) et en unités résiduelles.
struct PointIOB: Sendable, Equatable {
    let minutesDepuisMaintenant: Int
    let iob: Double
}

/// Assembleur **IOB** (Insulin On Board) — dérivation pure, non persistée.
///
/// Modèle **exponentiel** de référence (Loop / OpenAPS, dérivation Dragan
/// Maksimović / dm61), à deux paramètres physiologiques :
/// - `td` = durée d'action totale (DIA), depuis le profil ;
/// - `tp` = temps du pic d'activité, dérivé du type d'insuline (`InsulineRapide`).
///
/// Doc complète (formules, dérivation, sources) : Eraser « Diaviz — Modèle IOB
/// (insuline active) ». Toujours **factuel** : l'IOB est une estimation
/// affichée, jamais un conseil de dose.
enum IOBCalculateur {

    /// **Fraction de dose restante** (0…1) `t` minutes après une injection unique.
    ///
    ///   `IOB(t) = 1 − S·(1 − a)·[ (t²/(tau·td·(1−a)) − t/tau − 1)·e^(−t/tau) + 1 ]`
    ///
    /// avec `tau = tp·(1 − tp/td)/(1 − 2·tp/td)`, `a = 2·tau/td`,
    /// `S = 1/(1 − a + (1 + a)·e^(−td/tau))`.
    ///
    /// Le modèle exige `td > 2·tp` : on **clampe** `tp ≤ 0.45·td` pour rester
    /// défini quelle que soit la DIA saisie. Hors fenêtre : 1 avant, 0 après.
    nonisolated static func fractionRestante(
        minutes t: Double,
        diaMinutes td: Double,
        picMinutes picSouhaite: Double
    ) -> Double {
        guard t > 0 else { return 1 }
        guard t < td else { return 0 }
        let tp = min(max(picSouhaite, 1), 0.45 * td)
        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let S = 1 / (1 - a + (1 + a) * exp(-td / tau))
        return 1 - S * (1 - a) * ((t * t / (tau * td * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1)
    }

    /// IOB **total** à l'instant `instant` — somme des résidus des injections.
    nonisolated static func iob(
        a instant: Date,
        injections: [InjectionPourIOB],
        diaHeures: Double,
        picMinutes: Double
    ) -> Double {
        let td = diaHeures * 60
        return injections.reduce(0.0) { total, injection in
            let t = instant.timeIntervalSince(injection.heure) / 60
            return total + injection.dose * fractionRestante(minutes: t, diaMinutes: td, picMinutes: picMinutes)
        }
    }

    /// Courbe d'IOB total projetée depuis `debut`, par pas de 15 min sur
    /// `horizonMinutes` (défaut 6h). S'arrête dès que l'IOB tombe sous 0.05u
    /// (pas de queue plate), mais garde toujours le premier point (« maintenant »).
    nonisolated static func courbe(
        injections: [InjectionPourIOB],
        depuis debut: Date,
        diaHeures: Double,
        picMinutes: Double,
        horizonMinutes: Int = 360
    ) -> [PointIOB] {
        var points: [PointIOB] = []
        for minutes in stride(from: 0, through: horizonMinutes, by: 15) {
            let date = debut.addingTimeInterval(Double(minutes) * 60)
            let valeur = iob(a: date, injections: injections, diaHeures: diaHeures, picMinutes: picMinutes)
            points.append(PointIOB(minutesDepuisMaintenant: minutes, iob: valeur))
            if valeur < 0.05 && minutes > 0 { break }
        }
        return points
    }
}

// MARK: - Pic d'activité par type d'insuline

extension InsulineRapide {

    /// Temps du pic d'activité `tp` (minutes), dérivé du profil pharmacocinétique
    /// de l'insuline. Analogues rapides (aspart/lispro/glulisine) ≈ 75 min ;
    /// ultra-rapides (Fiasp/Lyumjev) ≈ 55 min. Voir doc Eraser « Modèle IOB ».
    var picActionMinutes: Double {
        switch self {
        case .novorapid, .humalog, .apidra: return 75
        case .fiasp, .lyumjev:              return 55
        case .autre:                        return 75
        }
    }
}
