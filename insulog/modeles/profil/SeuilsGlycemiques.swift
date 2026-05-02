//
//  SeuilsGlycemiques.swift
//  insulog
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Seuils glycémiques personnels (en mg/dL).
///
/// Sert à catégoriser visuellement chaque mesure : sous `hypoglycemie`
/// → zone rouge (hypo), au-dessus de `hyperglycemie` → zone orange
/// (hyper), entre les deux → zone cible. Les valeurs par défaut
/// (70 / 180 mg/dL) sont les recommandations standards du temps dans
/// la cible (TIR) — l'utilisateur peut les ajuster selon son médecin.
struct SeuilsGlycemiques: Codable, Equatable, Sendable {
    var hypoglycemie: Double
    var hyperglycemie: Double

    init(hypoglycemie: Double = 70, hyperglycemie: Double = 180) {
        self.hypoglycemie = hypoglycemie
        self.hyperglycemie = hyperglycemie
    }
}
