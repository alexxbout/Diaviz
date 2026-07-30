//
//  ContexteNormalise.swift
//  diaviz
//

import Foundation

/// Entrée normalisée du référentiel de contextes de repas — un événement de
/// vie réel (ex. « conduire »), désigné par un libellé + emoji stables, vers
/// lequel convergent plusieurs formulations brutes (`variantes`) au fil du
/// temps. Persisté par `ReferentielContextesService` (UserDefaults, JSON) —
/// pas un fait brut horodaté du hub, donc pas de `@Model` SwiftData ici.
struct ContexteNormalise: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var libelle: String
    var emoji: String
    /// Textes bruts déjà rattachés à cette entrée (dédupliqués, insensible à
    /// la casse) — alimente `suggestions(pour:)` pour le matching local.
    var variantes: [String]

    var affichage: String { "\(emoji) \(libelle)" }
}
