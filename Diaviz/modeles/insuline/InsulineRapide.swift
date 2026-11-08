//
//  InsulineRapide.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Marques d'insuline rapide (analogue) couramment prescrites en France.
///
/// La liste est volontairement finie pour limiter les fautes de frappe et
/// permettre des analyses cohérentes par marque ; l'option `.autre` ouvre
/// la porte aux cas non listés (rare).
nonisolated enum InsulineRapide: String, CaseIterable, Codable, Identifiable, Sendable {
    case novorapid = "Novorapid"
    case humalog   = "Humalog"
    case fiasp     = "Fiasp"
    case lyumjev   = "Lyumjev"
    case apidra    = "Apidra"
    case autre     = "Autre"

    var id: String { rawValue }
}
