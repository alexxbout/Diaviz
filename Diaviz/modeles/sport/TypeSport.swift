//
//  TypeSport.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation

/// Type de sport pratiqué — discriminant métier (impact glycémique
/// différent selon la nature de l'effort) et source d'attributs visuels
/// (emoji, libellé, catégorie) pour la liste, la sheet de saisie et le
/// graphe de la page Sport.
///
/// Le `rawValue` est la forme « titre » française pour réutilisation
/// directe en UI sans table de correspondance supplémentaire.
enum TypeSport: String, CaseIterable, Codable, Sendable, Hashable {
    case course          = "Course"
    case velo            = "Vélo"
    case natation        = "Natation"
    case marche          = "Marche"
    case musculation     = "Musculation"
    case yoga            = "Yoga"
    case sportCollectif  = "Sport collectif"
    case autre           = "Autre"

    // MARK: - Présentation

    /// Emoji représentatif — utilisé en tête de la `LigneActiviteSport`
    /// et dans la grille de la sheet de saisie. Pas de SF Symbol ici :
    /// l'emoji est plus reconnaissable et cohérent avec l'usage des
    /// emojis pour les aliments dans la page Repas.
    var emoji: String {
        switch self {
        case .course:          "🏃"
        case .velo:            "🚴"
        case .natation:        "🏊"
        case .marche:          "🚶"
        case .musculation:     "🏋"
        case .yoga:            "🧘"
        case .sportCollectif:  "⚽"
        case .autre:           "🏅"
        }
    }

    /// Catégorie agrégée — pilote la couleur des barres dans le graphe
    /// du jour (cardio rouge / muscu violet / autre bleu) et le résumé
    /// compact « 1 cardio · 1 autre ».
    var categorie: CategorieSport {
        switch self {
        case .course, .velo, .natation, .marche, .sportCollectif:
            return .cardio
        case .musculation:
            return .musculation
        case .yoga, .autre:
            return .autre
        }
    }
}
