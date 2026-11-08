//
//  MotifPause.swift
//  diaviz
//

import Foundation

/// Raison d'une période de pause (mode pause, principe CLAUDE.md). Pendant une
/// pause, les événements restent enregistrés mais sont **exclus des analyses**.
nonisolated enum MotifPause: String, Codable, Sendable, CaseIterable {
    case voyage
    case maladie
    case corticoides
    case autre
}
