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

    var totalGlucides: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }
}
