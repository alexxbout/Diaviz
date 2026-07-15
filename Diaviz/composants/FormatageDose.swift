//
//  FormatageDose.swift
//  diaviz
//

import Foundation

extension Double {

    /// Dose d'insuline compacte : « 4u » si entier, « 3.5u » sinon.
    ///
    /// Notation partagée par toutes les rows du domaine repas (journal, détail,
    /// aliment du repas) — évite le « 4.0u » et surtout la réécriture du même
    /// formatage dans chaque vue.
    var doseInsulineFormatee: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(self))u"
            : String(format: "%.1fu", self)
    }
}
