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

    /// Écart de dose avec signe explicite : « +1u », « −0.5u ».
    ///
    /// Pour un `Ajustement.valeur`, qui n'est pas une dose absolue mais un
    /// écart au ratio : sans le signe, « 1u » se lirait comme une dose de
    /// plus alors qu'il peut s'agir d'un retrait. Signe moins typographique
    /// (U+2212) et non le tiret ASCII, pour garder la même chasse que le
    /// « + » en `monospacedDigit`.
    var ecartDoseFormate: String {
        let magnitude = abs(self).doseInsulineFormatee
        if self < 0 { return "\u{2212}\(magnitude)" }
        return "+\(magnitude)"
    }
}
