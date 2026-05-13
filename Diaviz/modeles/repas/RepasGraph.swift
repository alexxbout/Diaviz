//
//  RepasGraph.swift
//  diaviz
//
//  Created by Alexandre on 30/04/2026.
//

import SwiftUI

enum VerdictGlycemique: Hashable, Codable, Sendable {
    case bon          // pic resté < 180 mg/dL
    case moyen        // pic entre 180-240 mg/dL
    case mauvais      // pic > 240 mg/dL ou hypo détectée
    case indetermine  // données pas encore disponibles

    var couleur: Color {
        switch self {
        case .bon: .green
        case .moyen: .orange
        case .mauvais: .red
        case .indetermine: .gray
        }
    }

    var libelle: String {
        switch self {
        case .bon: "Pic resté en cible"
        case .moyen: "Pic modéré"
        case .mauvais: "Pic élevé"
        case .indetermine: "En attente d'analyse"
        }
    }
}

struct RepasGraph: Identifiable, Hashable {
    let id: UUID
    let heure: Date
    let glucides: Double
    let aInjection: Bool
    let verdict: VerdictGlycemique
    let label: String
    let emoji: String

    init(
        id: UUID = UUID(),
        heure: Date,
        glucides: Double,
        aInjection: Bool,
        verdict: VerdictGlycemique,
        label: String,
        emoji: String
    ) {
        self.id = id
        self.heure = heure
        self.glucides = glucides
        self.aInjection = aInjection
        self.verdict = verdict
        self.label = label
        self.emoji = emoji
    }
}

extension RepasGraph {
    /// Convertit un `Repas` métier en projection pour le graphe.
    /// Le verdict est mocké tant que la corrélation CGM n'est pas branchée.
    init(_ repas: Repas, label: String) {
        self.init(
            id: repas.id,
            heure: repas.heure,
            glucides: Double(repas.totalGlucides),
            aInjection: repas.aliments.contains { $0.insuline > 0 },
            verdict: Self.verdictMock(pour: repas),
            label: label,
            emoji: repas.aliments.first?.emoji ?? "🍽️"
        )
    }

    /// Mock déterministe pour donner du relief visuel en attendant le CGM.
    private static func verdictMock(pour repas: Repas) -> VerdictGlycemique {
        let cal = Calendar.current
        let h = cal.component(.hour, from: repas.heure)
        let m = cal.component(.minute, from: repas.heure)
        switch (h * 60 + m) % 4 {
        case 0: return .bon
        case 1: return .indetermine
        case 2: return .moyen
        default: return .mauvais
        }
    }
}
