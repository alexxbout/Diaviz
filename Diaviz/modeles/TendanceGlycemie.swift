//
//  TendanceGlycemie.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import Foundation

/// Tendance de la glycémie au moment d'une mesure — la **trajectoire**, pas
/// seulement la photo. 110 qui descend vite ≠ 110 qui monte : même chiffre,
/// décision opposée. Cinq états calqués sur les flèches CGM (Dexcom).
///
/// Concept transverse (réutilisable partout où une glycémie est affichée).
/// Énumération pure : le symbole/flèche vit ici, le rendu dans la vue.
nonisolated enum TendanceGlycemie: String, Codable, Sendable, Equatable, CaseIterable {
    case forteHausse
    case hausse
    case stable
    case baisse
    case forteBaisse

    /// SF Symbol orienté (flèche) représentant la direction.
    var symbole: String {
        switch self {
        case .forteHausse: return "arrow.up"
        case .hausse:      return "arrow.up.right"
        case .stable:      return "arrow.right"
        case .baisse:      return "arrow.down.right"
        case .forteBaisse: return "arrow.down"
        }
    }

    var libelle: String {
        switch self {
        case .forteHausse: return "en forte hausse"
        case .hausse:      return "en hausse"
        case .stable:      return "stable"
        case .baisse:      return "en baisse"
        case .forteBaisse: return "en forte baisse"
        }
    }
}
