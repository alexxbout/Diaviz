//
//  MotifInjection.swift
//  diaviz
//

import Foundation

/// Motif métier derrière une injection — précise *pourquoi* la dose a été
/// faite, au-delà du simple `TypeInsuline`. Optionnel sur `Injection` : les
/// saisies anciennes ou ambiguës peuvent ne pas le renseigner.
///
/// Sert de **trigger à l'analyse B3** : une rapide `.correction` prise au
/// coucher déclenche l'analyse des corrections du soir (event-based, sans
/// seuil de glycémie).
nonisolated enum MotifInjection: String, Codable, Sendable, CaseIterable {
    /// Bolus accompagnant une prise alimentaire.
    case repas
    /// Rapide hors repas pour corriger une hyperglycémie.
    case correction
    /// Insuline lente quotidienne (basale).
    case basale
}
