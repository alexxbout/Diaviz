//
//  EmpreinteWidgetSnapshot.swift
//  diaviz
//
//  Instantané de l'empreinte du jour en cours, partagé avec le widget écran
//  d'accueil via App Group (`AppGroupe.identifiant`). L'app écrit après
//  chaque `ScoreService.recharger()` ; le widget lit seul, jamais d'écriture
//  côté extension. Process séparés → UserDefaults(suiteName:), pas de
//  SwiftData partagé (le widget n'ouvre pas le hub).
//
//  Dégradation gracieuse : instantané absent ou périmé (jour métabolique
//  différent de celui du widget au moment du rendu) → le widget affiche un
//  état neutre, jamais une empreinte trompeuse d'un autre jour.
//

import Foundation

nonisolated struct EmpreinteWidgetSnapshot: Codable, Sendable, Equatable {
    /// Jour métabolique (00h calendaire) auquel cet instantané se rapporte.
    let jour: Date
    let anneaux: [CalculEmpreinteGlycemique.Anneau]
    let score: Int?
    /// Date d'écriture — sert à détecter un instantané périmé si l'app ne
    /// tourne plus depuis longtemps (pas de garantie d'exécution en fond).
    let ecritLe: Date

    private static let cle = "empreinteWidgetSnapshot"

    static func ecrire(_ instantane: EmpreinteWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: AppGroupe.identifiant),
              let donnees = try? JSONEncoder().encode(instantane) else { return }
        defaults.set(donnees, forKey: cle)
    }

    static func lire() -> EmpreinteWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: AppGroupe.identifiant),
              let donnees = defaults.data(forKey: cle) else { return nil }
        return try? JSONDecoder().decode(EmpreinteWidgetSnapshot.self, from: donnees)
    }
}
