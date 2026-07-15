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
    /// Convertit un `Repas` métier en projection pour le graphe. Le verdict
    /// provient de la réponse glycémique dérivée du CGM (`Repas.etatAnalyse`,
    /// posée par `RepasService`) — `.indetermine` tant qu'elle n'est pas
    /// disponible (repas récent, sans bolus, ou CGM manquant).
    init(_ repas: Repas, label: String) {
        self.init(
            id: repas.id,
            heure: repas.heure,
            glucides: Double(repas.totalGlucides),
            aInjection: repas.aliments.contains { $0.insuline > 0 },
            verdict: Self.verdictDepuisEtat(pour: repas),
            label: label,
            emoji: repas.aliments.first?.emoji ?? "🍽️"
        )
    }

    /// Mappe l'`EtatAnalyse` du repas vers le verdict affiché : seule une
    /// analyse `disponible` porte un verdict coloré, les autres états
    /// (attente, données manquantes, sans injection, non calculé) restent
    /// `.indetermine`.
    private static func verdictDepuisEtat(pour repas: Repas) -> VerdictGlycemique {
        if case .disponible(let reponse) = repas.etatAnalyse {
            return reponse.verdict
        }
        return .indetermine
    }
}
