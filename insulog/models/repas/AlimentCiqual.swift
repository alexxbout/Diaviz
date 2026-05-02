//
//  AlimentCiqual.swift
//  insulog
//
//  Created by Alexandre on 27/04/2026.
//

import Foundation

struct AlimentCiqual: Codable, Identifiable, Hashable {
    let id: Int
    let nom: String
    let calories: Double
    let glucides: Double
    let sucres: Double
    let proteines: Double
    let lipides: Double
    let fibres: Double
    let emoji: String?
}

private extension String {
    func normaliser() -> String {
        self.lowercased().folding(options: .diacriticInsensitive, locale: .current)
    }
}

@Observable
final class CiqualService {
    static let shared = CiqualService()
    private(set) var aliments: [AlimentCiqual] = []

    private init() {
        chargerCiqual()
    }

    private func chargerCiqual() {
        guard let url = Bundle.main.url(forResource: "ciqual", withExtension: "json") else {
            print("Fichier ciqual.json introuvable")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            self.aliments = try JSONDecoder().decode([AlimentCiqual].self, from: data)
        } catch {
            print("Erreur de chargement CIQUAL : \(error)")
        }
    }

    /// Recherche à 5 niveaux de pertinence, avec boost des aliments récents.
    func rechercher(_ terme: String, limite: Int = 10) -> [AlimentCiqual] {
        let termeNormalise = terme
            .trimmingCharacters(in: .whitespaces)
            .normaliser()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !termeNormalise.isEmpty else { return [] }

        let mots = termeNormalise.split(separator: " ").map(String.init)

        var correspondanceExacte: [AlimentCiqual] = []
        var nomPrincipal: [AlimentCiqual] = []
        var commenceParTerme: [AlimentCiqual] = []
        var contientTerme: [AlimentCiqual] = []
        var tousMots: [AlimentCiqual] = []

        for aliment in aliments {
            let nom = aliment.nom.normaliser()
            if nom == termeNormalise {
                correspondanceExacte.append(aliment)
            } else if nom.hasPrefix(termeNormalise) {
                let suite = nom.dropFirst(termeNormalise.count)
                if suite.isEmpty || suite.hasPrefix(",") {
                    nomPrincipal.append(aliment)
                } else {
                    commenceParTerme.append(aliment)
                }
            } else if nom.contains(termeNormalise) {
                contientTerme.append(aliment)
            } else if mots.allSatisfy({ nom.contains($0) }) {
                tousMots.append(aliment)
            }
        }

        let ordonnes = correspondanceExacte + nomPrincipal + commenceParTerme + contientTerme + tousMots
        let recentsService = AlimentsRecentsService.shared

        return Array(
            ordonnes.sorted { lhs, rhs in
                switch (recentsService.position(lhs), recentsService.position(rhs)) {
                case (let a?, let b?): return a < b
                case (_?, nil):        return true
                case (nil, _?):        return false
                case (nil, nil):       return false
                }
            }
            .prefix(limite)
        )
    }
}
