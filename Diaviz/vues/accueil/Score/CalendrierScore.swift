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

/// Lundi 00:00 (locale) de la semaine contenant `jour`. Le calcul se
/// fait sur `startOfDay(jour)` pour éviter les sauts si `jour` tombe
/// pile à minuit (heure légale).
func lundiDeLaSemaine(_ jour: Date) -> Date {
    let cal = calendrierFrancais
    let weekday = cal.component(.weekday, from: jour) // 1=dim, 2=lun, ..., 7=sam
    let offsetVersLundi = (weekday + 5) % 7 // lun=0, mar=1, ..., dim=6
    let debutJour = cal.startOfDay(for: jour)
    return cal.date(byAdding: .day, value: -offsetVersLundi, to: debutJour) ?? debutJour
}

extension String {
    /// Met en majuscule la première lettre — utilisé pour les jours
    /// français qui ressortent en minuscules de `DateFormatter`.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
