//
//  EntreeAliment.swift
//  diaviz
//
//  Created by Alexandre on 28/04/2026.
//

import Foundation

/// Représente un aliment ajouté à un repas avec sa quantité et ses paramètres.
/// Contrairement à `ResultatRechercheAliment` qui décrit un aliment générique
/// (base CIQUAL ou produit Open Food Facts), `EntreeAliment` est une instance
/// concrète dans un repas : on sait combien de grammes l'utilisateur en a
/// mangé, si la quantité est approximative, etc.
struct EntreeAliment: Identifiable {
    let id = UUID()

    /// L'aliment de référence (brut CIQUAL ou produit OFF).
    let aliment: ResultatRechercheAliment

    /// Quantité consommée en grammes — reste la source de vérité pour tous
    /// les calculs (glucides, insuline…), quel que soit le mode de saisie.
    var quantiteGrammes: Double

    /// Mode de saisie utilisé pour arriver à `quantiteGrammes` (grammes
    /// directs ou nombre de portions). Mémorisé pour préremplir le même
    /// mode la prochaine fois que cet aliment est ajouté.
    var modeQuantite: ModeQuantiteAliment = .grammes

    /// Indique si l'utilisateur estime la quantité plutôt qu'il ne la mesure précisément.
    /// Utilisé pour pondérer la fiabilité de l'analyse nutritionnelle.
    var quantiteApproximative: Bool

    /// Dose d'insuline rapide associée à cet aliment (en unités).
    /// Optionnelle : l'utilisateur peut ne pas encore savoir quelle dose administrer.
    var doseInsuline: Double?

    /// Note libre associée à l'entrée (contexte, texture, ressenti, etc.).
    var note: String

    /// Aliment pris pour traiter une hypoglycémie (resucrage), plutôt qu'un
    /// aliment de repas ordinaire. Fait déclaré par l'utilisateur — sert de
    /// signal factuel pour les analyses futures (ex. distinguer un aliment
    /// de repas d'un resucrage dans le détail d'une nuit).
    var resucrage: Bool = false

    /// Nom et emoji tels qu'enregistrés, pour un aliment rouvert depuis un
    /// repas déjà saisi : modifier une quantité ne doit pas réécrire ces faits
    /// (la signature de « Repas à revoir » lit le nom). `nil` à la saisie.
    var nomFige: String? = nil
    var emojiFige: String? = nil

    /// Glucides calculés proportionnellement à la quantité consommée.
    var glucides: Double {
        aliment.glucides * quantiteGrammes / 100
    }
}
