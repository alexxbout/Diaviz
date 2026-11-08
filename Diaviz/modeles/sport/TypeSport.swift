//
//  TypeSport.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation

/// Type de sport pratiqué — discriminant métier (impact glycémique
/// différent selon la nature de l'effort) et source d'attributs visuels
/// (icône SF Symbol, libellé, catégorie) pour la liste, la sheet de saisie
/// et le graphe de la page Sport.
///
/// Le `rawValue` est la forme « titre » française pour réutilisation
/// directe en UI sans table de correspondance supplémentaire.
nonisolated enum TypeSport: String, CaseIterable, Codable, Sendable, Hashable {
    case course          = "Course"
    case velo            = "Vélo"
    case natation        = "Natation"
    case marche          = "Marche"
    case musculation     = "Musculation"
    case yoga            = "Yoga"
    case sportCollectif  = "Sport collectif"
    case tennis          = "Tennis"
    case badminton       = "Badminton"
    case randonnee       = "Randonnée"
    case escalade        = "Escalade"
    case ski             = "Ski"
    case aviron          = "Aviron"
    case danse           = "Danse"
    case hiit            = "HIIT"
    case autre           = "Autre"

    // MARK: - Présentation

    /// Nom du SF Symbol représentatif — utilisé en tête de la
    /// `LigneActiviteSport` et dans la grille de la sheet de saisie
    /// (`Image(systemName:)`, pas d'emoji : cohérence avec le reste de l'UI
    /// de l'app, qui n'utilise plus que des SF Symbols hors emoji d'aliments).
    var icone: String {
        switch self {
        case .course:          "figure.run"
        case .velo:            "figure.outdoor.cycle"
        case .natation:        "figure.pool.swim"
        case .marche:          "figure.walk"
        case .musculation:     "figure.strengthtraining.traditional"
        case .yoga:            "figure.yoga"
        case .sportCollectif:  "figure.soccer"
        case .tennis:          "figure.tennis"
        case .badminton:       "figure.badminton"
        case .randonnee:       "figure.hiking"
        case .escalade:        "figure.climbing"
        case .ski:             "figure.skiing.downhill"
        case .aviron:          "figure.rower"
        case .danse:           "figure.dance"
        case .hiit:            "figure.highintensity.intervaltraining"
        case .autre:           "medal.fill"
        }
    }

    /// Catégorie agrégée — pilote la couleur des barres dans le graphe
    /// du jour (cardio rouge / muscu violet / autre bleu) et le résumé
    /// compact « 1 cardio · 1 autre ».
    var categorie: CategorieSport {
        switch self {
        case .course, .velo, .natation, .marche, .sportCollectif,
             .tennis, .badminton, .randonnee, .ski, .aviron, .hiit:
            return .cardio
        case .musculation:
            return .musculation
        case .yoga, .escalade, .danse, .autre:
            return .autre
        }
    }
}
