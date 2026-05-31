//
//  ChargeActivite.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import Foundation

/// Charge d'activité sportive **sur la semaine glissante** (7 jours).
///
/// Signal de **contexte transverse** — pas spécifique à une analyse : l'effet
/// d'un entraînement sur la sensibilité à l'insuline dure 24-48h et se cumule
/// sur plusieurs séances. Une charge élevée explique des hypos qui paraissent
/// inexpliquées au niveau d'une seule soirée (sport non loggé ce soir-là mais
/// semaine chargée). Destiné à être affiché à plusieurs endroits (accueil,
/// analyses du coucher, recherche).
///
/// Énumération **pure** (sans dépendance UI) : le mapping couleur/symbole vit
/// dans `BadgeChargeActivite`. Les libellés/descriptions restent **factuels**,
/// jamais prescriptifs.
enum ChargeActivite: String, Sendable, Equatable, CaseIterable {
    case aucune
    case calme
    case moderee
    case intense

    var libelle: String {
        switch self {
        case .aucune:  return "Aucune activité"
        case .calme:   return "Semaine tranquille"
        case .moderee: return "Semaine moyenne"
        case .intense: return "Semaine intense"
        }
    }

    /// Fait court affiché dans le popover — défini par le nombre de séances sur
    /// 7 jours. Factuel, scannable d'un coup d'œil, aucun conseil.
    var descriptif: String {
        switch self {
        case .aucune:  return "0 séance sur 7 jours"
        case .calme:   return "1–2 séances sur 7 jours"
        case .moderee: return "3–4 séances sur 7 jours"
        case .intense: return "5 séances ou plus sur 7 jours"
        }
    }
}
