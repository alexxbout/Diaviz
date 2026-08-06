//
//  IntervallePauseSeance.swift
//  diaviz
//

import Foundation

/// Une fenêtre de pause **terminée** pendant une séance chronométrée en
/// direct — `[début, fin]` en horodatages absolus.
///
/// Distinct de `PeriodePause` (mode pause global de l'app — voyage,
/// maladie — qui exclut des données des analyses) : ceci ne concerne que
/// les pauses du chrono sportif, à l'échelle d'une seule séance.
///
/// Sert deux besoins posés lors du cadrage S1 : reconstituer le signal
/// « resucrage pendant une pause » (à venir, Lot 2/3), et corriger
/// `ActiviteSportive.dateFin`, qui sous-estimait la fin réelle en horloge
/// murale d'une séance avec pauses (`dureeMinutes` est la durée d'effort
/// net, pauses déjà déduites).
struct IntervallePauseSeance: Codable, Sendable, Hashable {
    let debut: Date
    let fin: Date

    var duree: TimeInterval { fin.timeIntervalSince(debut) }
}
