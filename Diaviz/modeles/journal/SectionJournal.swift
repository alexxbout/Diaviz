//
//  SectionJournal.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import Foundation

/// Identifie une des trois sous-sections du Journal — sert de
/// sélection pour le switcher de la barre minimisée custom posée
/// en bas de `JournalConteneurVue`.
enum SectionJournal: String, Hashable, CaseIterable, Identifiable {
    case repas
    case medications
    case sport

    var id: String { rawValue }

    /// SF Symbol affiché dans le segment du switcher.
    var sfSymbol: String {
        switch self {
        case .repas:       "fork.knife"
        case .medications: "syringe"
        case .sport:       "figure.run"
        }
    }

    /// Libellé long, utilisé pour l'`accessibilityLabel` du segment
    /// (le segment lui-même n'affiche que l'icône pour rester compact).
    var libelle: String {
        switch self {
        case .repas:       "Repas"
        case .medications: "Médications"
        case .sport:       "Sport"
        }
    }
}
