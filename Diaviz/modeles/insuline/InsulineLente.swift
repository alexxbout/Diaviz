//
//  InsulineLente.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Marques d'insuline lente (basale) couramment prescrites en France.
///
/// Pendante de `InsulineRapide` pour la configuration utilisateur.
/// `.autre` couvre les cas non listés ; le nom libre n'est pas géré ici
/// (l'app ne fait que noter le choix dans le profil).
nonisolated enum InsulineLente: String, CaseIterable, Codable, Identifiable, Sendable {
    case lantus  = "Lantus"
    case toujeo  = "Toujeo"
    case levemir = "Levemir"
    case tresiba = "Tresiba"
    case autre   = "Autre"

    var id: String { rawValue }
}
