//
//  ModeRatio.swift
//  insulog
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Mode de configuration du ratio insuline / glucides.
///
/// - `.unique` : un seul ratio appliqué pour tous les repas.
/// - `.parMoment` : un ratio distinct par moment de la journée
///   (petit-déjeuner / déjeuner / goûter / dîner).
///
/// La bascule entre les deux modes ne reporte volontairement aucune
/// valeur : c'est à l'utilisateur de saisir explicitement les nouveaux
/// ratios pour éviter des reports distraits.
enum ModeRatio: String, Codable, Sendable {
    case unique
    case parMoment
}
