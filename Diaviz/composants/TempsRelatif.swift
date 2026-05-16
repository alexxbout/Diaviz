//
//  TempsRelatif.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation

/// Libellé compact « il y a … » en français, calé sur la résolution
/// minute (la résolution des données de l'app).
///
/// Source unique de vérité — appelée par toutes les cartes qui affichent
/// l'âge d'un événement (dernier repas, dernière injection, dernier
/// site de lente). Centraliser ici évite les divergences de phrasing
/// d'un écran à l'autre.
///
/// Paliers :
/// - `< 60s` → « à l'instant »
/// - `< 1h`  → « il y a X min »
/// - `< 24h` → « il y a XhMM » (minutes zéro-paddées)
/// - `≥ 24h` → « il y a X j »
///
/// `maintenant` est paramétrable pour les tests / previews déterministes.
func tempsRelatif(depuis ancre: Date, maintenant: Date = .now) -> String {
    let secondes = max(0, maintenant.timeIntervalSince(ancre))
    let minutesTotales = Int(secondes / 60)

    if minutesTotales < 1 {
        return "à l'instant"
    }

    let heures = minutesTotales / 60
    if heures < 1 {
        return "il y a \(minutesTotales) min"
    }

    let jours = heures / 24
    if jours < 1 {
        let minutesRestantes = minutesTotales % 60
        return "il y a \(heures)h\(String(format: "%02d", minutesRestantes))"
    }

    return "il y a \(jours) j"
}
