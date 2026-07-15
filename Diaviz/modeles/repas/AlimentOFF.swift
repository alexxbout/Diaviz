//
//  AlimentOFF.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import Foundation

/// Un produit issu d'Open Food Facts (recherche texte ou scan futur).
/// Contrairement à `AlimentCiqual` (référentiel local exhaustif), les
/// nutriments OFF sont **optionnels** : la base est collaborative et certains
/// produits n'ont pas de valeurs renseignées. Un nutriment `nil` est affiché
/// « non renseigné » et compte pour 0 dans les calculs — signalé à l'écran.
struct AlimentOFF: Codable, Identifiable, Hashable {
    /// Code-barres du produit — identifiant naturel côté OFF.
    let code: String
    let nom: String
    let marque: String?
    /// Nutriments pour 100 g, tels que fournis par OFF.
    let calories: Double?
    let glucides: Double?
    let sucres: Double?
    let proteines: Double?
    let lipides: Double?
    let fibres: Double?
    /// Photo du produit (face avant) — miniature 200 px pour les listes.
    let imagePetiteURL: URL?
    /// Photo du produit (face avant) — 400 px pour la sheet de détail.
    let imageURL: URL?

    var id: String { code }

    /// Vrai si les glucides — la donnée vitale de l'app — sont renseignés.
    var glucidesRenseignes: Bool { glucides != nil }
}
