//
//  RepasAReevoirServiceMock.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation

// MARK: - RepasAReevoirServiceMock

/// Source mockée pour la section « Repas à revoir » de l'accueil.
///
/// Ne produit pour l'instant qu'un jeu fixe de 3 repas — Big Mac
/// (hyper modéré), Pizza (hyper sévère) et Sushi (en cible) — destiné
/// à exercer le rendu visuel de la `SectionRepasARevoir`. L'API
/// publique (`mock()`, `mockVide()`) reste un tableau de
/// `RepasARevoir` pour découpler la vue : quand la vraie source
/// (résultats ML pré-calculés) remplacera ce mock, la signature ne
/// changera pas.
enum RepasAReevoirServiceMock {

    /// Quatre repas couvrant les quatre situations visuelles : hyper
    /// modéré (orange), hyper sévère (rouge hyper), en cible (vert)
    /// et hypo post-prandiale (rouge hypo). Utilisé par les previews
    /// et par l'accueil en attendant la couche ML.
    static func mock() -> [RepasARevoir] {
        [
            .mockBigMac,
            .mockPizza,
            .mockSushi,
            .mockPadThai,
        ]
    }

    /// État neutre — la section « Repas à revoir » se masque alors
    /// entièrement plutôt que d'afficher une coquille vide.
    static func mockVide() -> [RepasARevoir] { [] }
}
