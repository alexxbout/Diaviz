//
//  PreferencesAvancees.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Préférences avancées du profil — repliées par défaut dans la sheet,
/// car peu de gens les modifient.
///
/// `margeAlerteDose` : écart toléré (en unités) entre la dose saisie
/// par l'utilisateur et la dose suggérée par son ratio avant de
/// déclencher un avertissement « cette dose s'écarte de votre ratio ».
/// L'app n'empêche jamais la saisie ; elle informe seulement.
struct PreferencesAvancees: Codable, Equatable, Sendable {
    var margeAlerteDose: Double

    init(margeAlerteDose: Double = 1) {
        self.margeAlerteDose = margeAlerteDose
    }
}
