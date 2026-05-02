//
//  SourceActivite.swift
//  insulog
//
//  Created by Alexandre on 02/05/2026.
//

import Foundation

/// Provenance d'une `ActiviteSportive`. Discrimine les saisies manuelles
/// (utilisateur dans la sheet « Nouvelle activité ») des activités
/// importées depuis Apple Santé (HealthKit) — détectées automatiquement
/// par l'Apple Watch.
///
/// Sert de drapeau d'affichage (footer « Source : Apple Santé » dans la
/// `LigneActiviteSport`) et conditionne la disponibilité des données
/// associées (`healthKitData` n'est rempli que pour `.healthKit`).
enum SourceActivite: String, Codable, Sendable, Hashable {
    case manuel
    case healthKit
}
