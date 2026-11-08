//
//  CalculVerrouRatio.swift
//  diaviz
//

import Foundation

/// Délai entre deux changements d'un ratio glucides / insuline. Chaque
/// changement fait repartir l'analyse du moment de zéro : des changements
/// trop rapprochés empêcheraient tout constat sur le réglage en cours.
///
/// Le ratio redevient modifiable au **premier** atteint des deux seuils. Le
/// délai en jours évite un blocage sans fin sur un moment rare (goûter).
nonisolated enum CalculVerrouRatio {

    static let repasRequis = 5
    static let joursRequis = 14

    enum Etat: Equatable {
        case libre
        case verrouille(repasRestants: Int, deblocage: Date)
    }

    /// `dateChangement` à `nil` : ratio jamais modifié, donc jamais verrouillé.
    /// La date de déblocage est un début de journée, celle affichée à l'écran.
    static func etat(
        dateChangement: Date?,
        repasDepuis: Int,
        maintenant: Date,
        calendrier: Calendar = .current
    ) -> Etat {
        guard let dateChangement, repasDepuis < repasRequis else { return .libre }
        let jour = calendrier.startOfDay(for: dateChangement)
        guard
            let deblocage = calendrier.date(byAdding: .day, value: joursRequis, to: jour),
            maintenant < deblocage
        else { return .libre }
        return .verrouille(repasRestants: repasRequis - repasDepuis, deblocage: deblocage)
    }
}
