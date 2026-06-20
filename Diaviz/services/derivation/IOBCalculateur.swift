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
/// Calcule l'insuline rapide encore active à partir des injections récentes et
/// de la **DIA** (durée d'action, depuis le profil). « Un hub, des dérivations » :
/// rien n'est stocké, tout est recalculé à la volée depuis des faits bruts.
///
/// Modèle de décroissance **bicubique Hermite** (C¹ partout) : deux cubiques
/// `smoothstep` raccordées au pic d'activité, dérivée nulle aux extrémités. La
/// somme de plusieurs injections reste lisse (pas de cassure à chaque pic).
///
/// Toujours **factuel** : l'IOB est une estimation affichée, jamais un conseil
/// de dose.
enum IOBCalculateur {

    /// Pic d'activité par défaut (min) — calé sur un analogue rapide moderne
    /// (NovoRapid, Humalog). V2 : dériver du type d'insuline rapide du profil
    /// (ultra-rapides Fiasp/Lyumjev ≈ 55 min).
    static let picParDefautMinutes: Double = 75

    /// IOB résiduel d'une **injection unique** `minutesEcoulees` après l'injection.
    ///
    /// - `0 → pic` (absorption) : de `dose` à `0.6·dose`, pente nulle à l'origine.
    /// - `pic → dia` (consommation) : de `0.6·dose` à `0`, pente nulle à la fin.
    ///
    /// Avant l'injection (`minutesEcoulees < 0`) : dose pleine. Au-delà de `dia` : 0.
    nonisolated static func iobResiduel(
        dose: Double,
        minutesEcoulees: Double,
        diaMinutes: Double,
        picMinutes: Double = picParDefautMinutes
    ) -> Double {
        guard minutesEcoulees >= 0 else { return dose }
        guard minutesEcoulees < diaMinutes else { return 0 }

        // `u²(3 - 2u)` : 0 → 1, dérivée nulle aux deux bouts → continuité C¹.
        func smoothstep(_ u: Double) -> Double { u * u * (3 - 2 * u) }

        if minutesEcoulees <= picMinutes {
            let u = minutesEcoulees / picMinutes
            return dose * (1 - 0.4 * smoothstep(u))
        }
        let u = (minutesEcoulees - picMinutes) / (diaMinutes - picMinutes)
        return dose * 0.6 * (1 - smoothstep(u))
    }

    /// IOB **total** à l'instant `instant` — somme des résidus des injections.
    nonisolated static func iob(
        a instant: Date,
        injections: [InjectionPourIOB],
        diaHeures: Double,
        picMinutes: Double = picParDefautMinutes
    ) -> Double {
        let dia = diaHeures * 60
        return injections.reduce(0.0) { total, injection in
            let elapsed = instant.timeIntervalSince(injection.heure) / 60
            return total + iobResiduel(
                dose: injection.dose,
                minutesEcoulees: elapsed,
                diaMinutes: dia,
                picMinutes: picMinutes
            )
        }
    }

    /// Courbe d'IOB total projetée depuis `debut`, par pas de 15 min sur
    /// `horizonMinutes` (défaut 6h). S'arrête dès que l'IOB tombe sous 0.05u
    /// (pas de queue plate), mais garde toujours le premier point (« maintenant »).
    nonisolated static func courbe(
        injections: [InjectionPourIOB],
        depuis debut: Date,
        diaHeures: Double,
        picMinutes: Double = picParDefautMinutes,
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
