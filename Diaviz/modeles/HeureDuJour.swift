//
//  HeureDuJour.swift
//  diaviz
//

import Foundation

/// Heure du jour mémorisée comme couple (heure, minute), indépendante de la
/// date. Sert au paramétrage de l'heure habituelle de la lente.
struct HeureDuJour: Sendable, Equatable {
    let heure: Int
    let minute: Int

    /// Projette `(heure, minute)` sur la journée `jour` (par défaut
    /// aujourd'hui), pour comparaison avec `Date.now`.
    func date(pour jour: Date = Date()) -> Date {
        Calendar.current.date(
            bySettingHour: heure,
            minute: minute,
            second: 0,
            of: jour
        ) ?? jour
    }

    /// Format affichage 24h (« 22:00 »).
    var libelle: String {
        String(format: "%02d:%02d", heure, minute)
    }
}
