//
//  HorairesRepas.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Horaires habituels des quatre repas de la journée.
///
/// Ces dates ne sont utilisées que pour leur composante heure / minute :
/// la partie « jour » est volontairement fixée au jour courant à la
/// création — la vue n'expose qu'un `DatePicker` `.hourAndMinute`.
///
/// Sert à catégoriser automatiquement un repas saisi (« 12:34 » →
/// déjeuner) selon sa proximité avec ces horaires.
struct HorairesRepas: Codable, Equatable, Sendable {
    var petitDejeuner: Date
    var dejeuner: Date
    var gouter: Date
    var diner: Date

    /// Construit un `HorairesRepas` à partir de quatre couples
    /// (heure, minute), projetés sur le jour courant. Tombe en arrière
    /// sur l'heure courante si le calendrier refuse la projection — cas
    /// improbable mais évite un `Date()` non déterministe en cascade.
    static func defaut(calendar: Calendar = .current) -> HorairesRepas {
        let aujourdhui = Date()

        func date(_ h: Int, _ m: Int) -> Date {
            calendar.date(
                bySettingHour: h,
                minute: m,
                second: 0,
                of: aujourdhui
            ) ?? aujourdhui
        }

        return HorairesRepas(
            petitDejeuner: date(7, 0),
            dejeuner:      date(12, 0),
            gouter:        date(16, 0),
            diner:         date(19, 30)
        )
    }
}
