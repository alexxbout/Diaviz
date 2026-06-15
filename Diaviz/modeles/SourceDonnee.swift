//
//  SourceDonnee.swift
//  diaviz
//
//  Created by Alexandre on 14/06/2026.
//

import Foundation

/// Provenance d'un événement du hub. Présent sur chaque entité ingérable pour
/// tracer l'origine de la donnée et arbitrer les doublons (ex : CGM Dexcom vs
/// HealthKit). Énumération transverse au hub d'événements.
enum SourceDonnee: String, Codable, Sendable, Equatable, CaseIterable {
    case dexcom
    case healthkit
    case manuel
}
