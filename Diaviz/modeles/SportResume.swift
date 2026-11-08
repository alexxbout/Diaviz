//
//  SportResume.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import Foundation

/// Résumé d'une séance de sport rattachée à une soirée — assez riche pour
/// mériter un détail au tap (type + intensité + durée) plutôt qu'une valeur
/// inline. Contexte transverse (coucher, corrections, etc.).
nonisolated struct SportResume: Sendable, Equatable {

    let type: String           // ex. « Course », « Vélo »
    let intensite: String      // ex. « léger », « modéré », « intense »
    let dureeMinutes: Int

    var dureeTexte: String {
        if dureeMinutes < 60 { return "\(dureeMinutes) min" }
        let h = dureeMinutes / 60
        let m = dureeMinutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }

    /// Phrase compacte affichée dans le popover / l'accessibilité.
    var resume: String { "\(type) · \(intensite) · \(dureeTexte)" }
}
