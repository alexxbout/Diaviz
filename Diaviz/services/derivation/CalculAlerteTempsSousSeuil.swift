//
//  CalculAlerteTempsSousSeuil.swift
//  diaviz
//

import Foundation

/// Alerte « temps sous 70 mg/dL » : la **moyenne** des 3 derniers jours
/// terminés dépasse 3 %. Pur — reçoit le temps sous 70 de chaque jour déjà
/// calculé par le score quotidien (`FaitsJour.tbrLevel1 + tbrLevel2`), ne
/// relit pas le CGM.
///
/// Jours terminés (06h→06h), pas les 72 dernières heures : même découpage et
/// même couverture minimale que le score, donc aucun jour partiel qui ferait
/// bouger le chiffre toute la journée. Un jour sans couverture suffisante est
/// absent (`nil`), jamais compté à 0 % — ce serait dire « aucune hypo ».
///
/// Peu de recul → pas d'alerte : sous `joursMinimum` jours exploitables, la
/// moyenne ne repose sur presque rien. Mieux vaut se taire qu'afficher un
/// chiffre fragile en rouge.
nonisolated enum CalculAlerteTempsSousSeuil {

    /// Seuil de la moyenne, en % du temps — dépassé strictement.
    static let seuilPourcent = 3.0
    /// Nombre de jours terminés regardés.
    static let nombreJours = 3
    /// Jours exploitables minimum pour évaluer la moyenne.
    static let joursMinimum = 2

    struct Resultat: Equatable, Sendable {
        /// Moyenne du temps sous 70 sur les jours exploitables (%).
        let moyenne: Double
        /// Temps sous 70 de chaque jour, du plus ancien au plus récent ;
        /// `nil` = jour sans donnée exploitable.
        let parJour: [Double?]
    }

    /// `nil` si pas assez de jours exploitables, ou moyenne sous le seuil.
    static func evaluer(parJour: [Double?]) -> Resultat? {
        let valeurs = parJour.compactMap { $0 }
        guard valeurs.count >= joursMinimum else { return nil }
        let moyenne = valeurs.reduce(0, +) / Double(valeurs.count)
        guard moyenne > seuilPourcent else { return nil }
        return Resultat(moyenne: moyenne, parJour: parJour)
    }
}
