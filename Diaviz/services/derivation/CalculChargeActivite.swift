//
//  CalculChargeActivite.swift
//  diaviz
//

import Foundation

/// Classe la charge d'activité sportive sur une fenêtre de **7 jours
/// glissants** se terminant à une date donnée (incluse). Seuils alignés sur
/// `ChargeActivite.descriptif` (0 / 1-2 / 3-4 / 5+ séances).
///
/// Signal de **contexte transverse**, réutilisable par toutes les analyses qui
/// l'affichent (accueil, B2, B3) — pure, sans dépendance au hub ni à
/// `ActivitesSportService`.
nonisolated enum CalculChargeActivite {

    /// - Parameter activites: séances `(début, durée)` — la durée n'entre pas
    ///   dans le calcul (seul le **nombre** de séances compte, par construction
    ///   de `ChargeActivite.descriptif`), gardée pour un futur affinage.
    static func charge(
        jusqua date: Date,
        activites: [(debut: Date, dureeMin: Int)]
    ) -> ChargeActivite {
        let debutFenetre = date.addingTimeInterval(-7 * 86_400)
        let compte = activites.filter { $0.debut > debutFenetre && $0.debut <= date }.count
        switch compte {
        case 0:     return .aucune
        case 1...2: return .calme
        case 3...4: return .moderee
        default:    return .intense
        }
    }
}
