//
//  ClassementManuelNuit.swift
//  diaviz
//

import Foundation

/// Statut d'une nuit B1, tel que l'utilisateur peut l'imposer à la place du
/// calcul. Conservé dans le profil (synchronisé iCloud, repris par l'export
/// JSON), par jour du soir de la nuit.
nonisolated enum ClassementManuelNuit: String, Codable, Sendable, CaseIterable, Identifiable {
    case concluante
    case deriveMontante
    case deriveDescendante
    case hypo
    case ecartee

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .concluante:        return "Concluante"
        case .deriveMontante:    return "Dérive montante"
        case .deriveDescendante: return "Dérive descendante"
        case .hypo:              return "Hypo"
        case .ecartee:           return "Écartée"
        }
    }

    /// Catégorie de la nuit dans le verdict ; `nil` si elle n'y compte pas.
    var categorie: CategorieNuit? {
        switch self {
        case .concluante:                return .stable
        case .deriveMontante:            return .tendanceHaute
        case .deriveDescendante, .hypo:  return .tendanceBasse
        case .ecartee:                   return nil
        }
    }

    /// Clé de stockage : le jour du soir de la nuit, stable d'un appareil à
    /// l'autre tant que le fuseau ne change pas (« 2026-11-05 »).
    static func cle(pour dateNuit: Date, calendrier cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: dateNuit)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
