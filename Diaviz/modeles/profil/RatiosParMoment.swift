//
//  RatiosParMoment.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Ratios insuline / glucides distincts par moment de la journée.
///
/// Chaque champ est exprimé en grammes de glucides couverts par 1 unité
/// d'insuline rapide (« 1u / Xg »). Tous les champs sont optionnels :
/// un profil neuf n'a aucun ratio renseigné, et la vue affiche un état
/// « Requis » tant que les quatre ne sont pas saisis.
nonisolated struct RatiosParMoment: Codable, Equatable, Sendable {
    var petitDejeuner: Double?
    var dejeuner: Double?
    var gouter: Double?
    var diner: Double?

    /// `true` si les quatre ratios sont renseignés — pré-requis pour
    /// que les analyses statistiques par moment soient utilisables.
    var estComplete: Bool {
        petitDejeuner != nil
            && dejeuner != nil
            && gouter != nil
            && diner != nil
    }

    /// Constructeur vide — utilisé au reset lors de la bascule de mode
    /// et pour le mock « profil neuf ».
    init(
        petitDejeuner: Double? = nil,
        dejeuner: Double? = nil,
        gouter: Double? = nil,
        diner: Double? = nil
    ) {
        self.petitDejeuner = petitDejeuner
        self.dejeuner = dejeuner
        self.gouter = gouter
        self.diner = diner
    }
}
