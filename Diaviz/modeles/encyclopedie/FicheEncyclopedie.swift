//
//  FicheEncyclopedie.swift
//  diaviz
//

import Foundation

/// Une fiche de la bibliothèque : le résumé d'un point établi par la
/// littérature scientifique, avec ses sources.
///
/// **Ce que c'est** : de la documentation, consultable à part. Ce que les
/// études disent, formulé au constat.
///
/// **Ce que ce n'est pas** : un conseil. Une fiche ne croise jamais les
/// données de l'utilisateur, ne mentionne jamais sa glycémie du moment, et
/// ne dit jamais quoi faire. Croiser les deux transformerait une
/// bibliothèque en conseiller personnalisé — exactement ce que l'app
/// s'interdit (cf. principes du projet, CLAUDE.md).
///
/// Contenu figé dans le binaire (`CatalogueEncyclopedie`), pas de réseau ni
/// de persistance : ces synthèses évoluent au rythme des analyses qu'on
/// construit, pas à celui de l'utilisateur.
struct FicheEncyclopedie: Identifiable, Hashable {
    let id: String
    let titre: String
    /// Une phrase, affichée en sous-titre dans la liste.
    let resume: String
    let icone: String
    let theme: ThemeEncyclopedie
    /// Corps de la fiche, en paragraphes courts.
    let sections: [SectionFiche]
    let sources: [SourceEncyclopedie]
    /// Analyses de l'app que cette fiche éclaire — pur repère de lecture,
    /// aucun lien avec les données de l'utilisateur.
    let analysesLiees: [String]

    struct SectionFiche: Identifiable, Hashable {
        let id = UUID()
        let titre: String
        let texte: String
        /// Points énumérés sous le texte, quand la source donne des valeurs.
        var points: [String] = []
    }
}

struct SourceEncyclopedie: Identifiable, Hashable {
    let id = UUID()
    let titre: String
    let reference: String
    let url: URL?
}

enum ThemeEncyclopedie: String, CaseIterable, Identifiable {
    case mesure = "Mesurer l'équilibre"
    case sport = "Activité sportive"
    case hypoglycemie = "Hypoglycémie"
    case nuit = "Nuit et insuline lente"

    var id: String { rawValue }

    var icone: String {
        switch self {
        case .mesure:        "chart.bar.fill"
        case .sport:         "figure.run"
        case .hypoglycemie:  "arrow.down.circle.fill"
        case .nuit:          "moon.stars.fill"
        }
    }
}
