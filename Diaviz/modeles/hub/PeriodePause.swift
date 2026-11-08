//
//  PeriodePause.swift
//  diaviz
//

import Foundation
import SwiftData

/// Intervalle pendant lequel les données sont enregistrées mais **exclues des
/// analyses** (voyage, maladie, corticoïdes…). Les assembleurs filtrent tout
/// événement dont la `date` tombe dans une `PeriodePause`.
@Model
nonisolated final class PeriodePause {
    /// Début de la pause (horodatage absolu).
    var debut: Date = Date.distantPast
    /// Fin de la pause. `nil` = pause toujours en cours.
    var fin: Date?
    var motif: MotifPause = MotifPause.voyage
    var note: String?

    init(debut: Date, fin: Date? = nil, motif: MotifPause, note: String? = nil) {
        self.debut = debut
        self.fin = fin
        self.motif = motif
        self.note = note
    }
}

extension PeriodePause {
    /// `true` si `instant` tombe dans cette pause (fin ouverte si `fin == nil`).
    func contient(_ instant: Date) -> Bool {
        instant >= debut && (fin.map { instant <= $0 } ?? true)
    }
}
