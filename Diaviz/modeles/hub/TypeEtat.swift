//
//  TypeEtat.swift
//  diaviz
//

import Foundation

/// Nature d'un état subjectif déclaré par l'utilisateur (cible analyse E1 —
/// corrélation état ↔ glycémie). Fait brut horodaté du hub, jamais un verdict.
enum TypeEtat: String, Codable, Sendable, CaseIterable {
    case stress
    case maladie
    case manqueSommeil
    case cycle
    case alcool
    case autre
}
