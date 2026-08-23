//
//  ResultatRechercheAliment.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import Foundation

/// Résultat de recherche unifié : aliment brut CIQUAL ou produit Open Food
/// Facts. Les vues de saisie (ligne de résultat, sheet de détail,
/// `EntreeAliment`) consomment ce type unique au lieu d'être câblées sur une
/// source précise.
///
/// Enum plutôt que protocole : deux cas fermés, pattern-matching direct,
/// `Hashable`/`Identifiable`/`Codable` sans existentiel.
enum ResultatRechercheAliment: Identifiable, Hashable, Codable {
    case ciqual(AlimentCiqual)
    case off(AlimentOFF)

    /// Identifiant stable et composite — sert aussi de clé « récents ».
    var id: String {
        switch self {
        case .ciqual(let a): return "ciqual:\(a.id)"
        case .off(let p):    return "off:\(p.code)"
        }
    }

    // MARK: - Propriétés communes

    /// Nom personnalisé (CIQUAL uniquement, `NomsPersonnalisesService`) s'il
    /// existe, sinon le nom d'origine — seul point d'injection du
    /// renommage, propage automatiquement à toute vue consommant ce type.
    var nom: String {
        switch self {
        case .ciqual(let a): return NomsPersonnalisesService.shared.nom(pour: a)
        case .off(let p):    return p.nom
        }
    }

    /// Marque du produit — uniquement pour OFF.
    var marque: String? {
        switch self {
        case .ciqual: return nil
        case .off(let p): return p.marque
        }
    }

    var emoji: String? {
        switch self {
        case .ciqual(let a): return NomsPersonnalisesService.shared.emoji(pour: a)
        case .off:           return nil
        }
    }

    /// Photo miniature (200 px) — uniquement pour OFF, pour les listes.
    var imagePetiteURL: URL? {
        switch self {
        case .ciqual: return nil
        case .off(let p): return p.imagePetiteURL
        }
    }

    /// Photo (400 px) — uniquement pour OFF, pour la sheet de détail.
    var imageURL: URL? {
        switch self {
        case .ciqual: return nil
        case .off(let p): return p.imageURL
        }
    }

    /// Nutriments pour 100 g. Côté OFF, une valeur manquante vaut 0 dans les
    /// calculs — `glucidesRenseignes` permet de le signaler à l'écran.
    var calories: Double  { valeur(\.calories,  \.calories) }
    var glucides: Double  { valeur(\.glucides,  \.glucides) }
    var sucres: Double    { valeur(\.sucres,    \.sucres) }
    var proteines: Double { valeur(\.proteines, \.proteines) }
    var lipides: Double   { valeur(\.lipides,   \.lipides) }
    var fibres: Double    { valeur(\.fibres,    \.fibres) }

    /// Faux uniquement pour un produit OFF sans glucides renseignés.
    var glucidesRenseignes: Bool {
        switch self {
        case .ciqual:     return true
        case .off(let p): return p.glucidesRenseignes
        }
    }

    /// Faux uniquement pour un produit OFF sans énergie renseignée — CIQUAL
    /// couvre toujours ce nutriment.
    var caloriesRenseignees: Bool {
        switch self {
        case .ciqual:     return true
        case .off(let p): return p.caloriesRenseignees
        }
    }

    private func valeur(
        _ cheminCiqual: KeyPath<AlimentCiqual, Double>,
        _ cheminOFF: KeyPath<AlimentOFF, Double?>
    ) -> Double {
        switch self {
        case .ciqual(let a): return a[keyPath: cheminCiqual]
        case .off(let p):    return p[keyPath: cheminOFF] ?? 0
        }
    }
}
