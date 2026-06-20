//
//  Medicament.swift
//  diaviz
//

import Foundation
import SwiftData

/// Prise (ou traitement de fond) d'un médicament autre que l'insuline — ex.
/// corticoïdes, qui élèvent fortement la glycémie (cible analyse M1). Fait brut
/// horodaté, saisi manuellement.
@Model
final class Medicament {
    /// Horodatage absolu de la prise (ou du début, si récurrent).
    var date: Date
    var nom: String
    /// Dose libre (« 20 mg », « 2 comprimés »). `nil` si non renseignée.
    var dose: String?
    /// `true` = traitement de fond récurrent ; `false` = prise ponctuelle.
    var recurrent: Bool
    var note: String?

    init(date: Date, nom: String, dose: String? = nil, recurrent: Bool = false, note: String? = nil) {
        self.date = date
        self.nom = nom
        self.dose = dose
        self.recurrent = recurrent
        self.note = note
    }
}
