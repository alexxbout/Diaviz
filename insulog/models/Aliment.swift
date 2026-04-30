//
//  Aliment.swift
//  insulog
//
//  Created by Alexandre on 22/04/2026.
//

import Foundation

struct Aliment: Identifiable {
    let id = UUID()
    let emoji: String
    let nom: String
    let quantite: Int
    let glucides: Int
    let insuline: Double
}

struct Repas: Identifiable {
    let id = UUID()
    let heure: Date
    var aliments: [Aliment]
    /// État du pré-calcul de la réponse glycémique. `nil` quand l'app n'a
    /// pas encore reçu d'information du backend (cas par défaut pour les
    /// previews/données legacy). La valeur par défaut `nil` est nécessaire
    /// pour préserver les call-sites historiques `Repas(heure:, aliments:)`.
    var etatAnalyse: EtatAnalyse? = nil

    var totalGlucides: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }

    /// Total d'insuline injectée pour le repas, somme des doses par aliment.
    var totalInsuline: Double {
        aliments.reduce(0) { $0 + $1.insuline }
    }

    /// Indique si au moins un aliment a une dose d'insuline associée.
    /// Sert à différencier un repas "logué pour mémoire" d'un repas avec bolus.
    var aUneInjection: Bool {
        totalInsuline > 0
    }

    /// Emoji représentatif du repas : on prend l'aliment le plus contributeur
    /// en glucides — c'est lui qui pilote la réponse glycémique. À défaut
    /// (repas vide), un emoji générique.
    var emojiPrincipal: String {
        aliments.max(by: { $0.glucides < $1.glucides })?.emoji ?? "🍽"
    }
}
