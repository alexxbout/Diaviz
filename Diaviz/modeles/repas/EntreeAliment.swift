//
//  EntreeAliment.swift
//  diaviz
//
//  Created by Alexandre on 28/04/2026.
//

import Foundation

/// Représente un aliment ajouté à un repas avec sa quantité et ses paramètres.
/// Contrairement à `AlimentCiqual` qui décrit un aliment générique dans la base CIQUAL,
/// `EntreeAliment` est une instance concrète dans un repas : on sait combien de grammes
/// l'utilisateur en a mangé, si la quantité est approximative, etc.
struct EntreeAliment: Identifiable {
    let id = UUID()

    /// L'aliment de référence issu de la base CIQUAL.
    let aliment: AlimentCiqual

    /// Quantité consommée en grammes.
    var quantiteGrammes: Double

    /// Indique si l'utilisateur estime la quantité plutôt qu'il ne la mesure précisément.
    /// Utilisé pour pondérer la fiabilité de l'analyse nutritionnelle.
    var quantiteApproximative: Bool

    /// Dose d'insuline rapide associée à cet aliment (en unités).
    /// Optionnelle : l'utilisateur peut ne pas encore savoir quelle dose administrer.
    var doseInsuline: Double?

    /// Note libre associée à l'entrée (contexte, texture, ressenti, etc.).
    var note: String

    /// Glucides calculés proportionnellement à la quantité consommée.
    var glucides: Double {
        aliment.glucides * quantiteGrammes / 100
    }
}
