//
//  CalendrierScore.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation

/// Calendrier grégorien forcé en lundi-premier — utilisé partout dans
/// les vues du score pour ne pas dépendre des préférences système
/// (US = dimanche premier).
var calendrierFrancais: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2 // 1=dimanche, 2=lundi
    cal.locale = Locale(identifier: "fr_FR")
    return cal
}

extension String {
    /// Met en majuscule la première lettre — utilisé pour les jours
    /// français qui ressortent en minuscules de `DateFormatter`.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
