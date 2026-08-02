//
//  ModeQuantiteAliment.swift
//  diaviz
//

import Foundation

/// Mode de saisie de la quantité d'un aliment : grammes directs, ou nombre
/// de portions d'une taille définie par l'utilisateur pour cet aliment.
/// Ni CIQUAL ni Open Food Facts n'exposent de taille de portion exploitable
/// ici — c'est une méta-donnée purement locale, propre à Diaviz.
enum ModeQuantiteAliment: String, Codable {
    case grammes
    case portions
}
