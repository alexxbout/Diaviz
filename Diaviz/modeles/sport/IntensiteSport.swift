//
//  IntensiteSport.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation

/// Intensité ressentie de l'effort. Classification subjective à 3
/// niveaux (BORG simplifié) — résolution adaptée à un journal personnel,
/// la précision d'une zone de fréquence cardiaque n'apporte rien sans
/// capteur cardiaque relié.
///
/// Servira à corréler la baisse de glycémie avec l'intensité réelle
/// (« mes courses intenses font baisser de 30 mg/dL en 45min »).
enum IntensiteSport: String, CaseIterable, Codable, Sendable, Hashable {
    case faible    = "Faible"
    case moderee   = "Modérée"
    case intense   = "Intense"

    /// Description textuelle d'une dizaine de mots — affichée en sous-
    /// titre des cards radio de la sheet de saisie pour aider le choix.
    /// Garde un registre concret (« conversation possible »,
    /// « essoufflement ») plutôt que des plages de FC, plus parlant
    /// pour un usage personnel.
    var description: String {
        switch self {
        case .faible:   "Récupération, marche lente"
        case .moderee:  "Effort confortable, conversation possible"
        case .intense:  "Effort soutenu, essoufflement"
        }
    }
}
