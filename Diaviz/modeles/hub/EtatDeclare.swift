//
//  EtatDeclare.swift
//  diaviz
//

import Foundation
import SwiftData

/// État subjectif déclaré à un instant donné (cible analyse E1). Fait brut du
/// hub : on note *quoi* et *quand*, jamais d'interprétation. Saisie manuelle
/// uniquement, d'où l'absence de `source` (toujours l'utilisateur).
@Model
final class EtatDeclare {
    /// Horodatage absolu de la déclaration (clé de tri / découpage).
    var date: Date = Date.distantPast
    var type: TypeEtat = TypeEtat.stress
    /// Échelle subjective d'intensité, libre (ex. 1–5). `nil` si non renseignée.
    var intensite: Int?
    var note: String?

    init(date: Date, type: TypeEtat, intensite: Int? = nil, note: String? = nil) {
        self.date = date
        self.type = type
        self.intensite = intensite
        self.note = note
    }
}
