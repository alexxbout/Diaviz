//
//  ChangementParametre.swift
//  diaviz
//

import Foundation
import SwiftData

/// Paramètre de réglage dont l'historique est conservé — tous ceux qu'une
/// analyse compare ou segmente, à l'exception de la dose de lente, que
/// `CalculAnalyseBasale.doseHistory(lentes:)` reconstitue déjà depuis les
/// injections du hub.
///
/// Stocké en base par `rawValue` (voir `ChangementParametre.parametreBrut`) :
/// renommer un cas casserait la lecture des lignes déjà enregistrées.
enum ParametreSuivi: String, CaseIterable, Codable, Sendable {
    case ratioUnique
    case ratioPetitDejeuner
    case ratioDejeuner
    case ratioGouter
    case ratioDiner
    /// ISF, en mg/dL par unité.
    case facteurCorrection
    /// Ratio post-effort d'un type de sport — qualifié par
    /// `CleParametre.typeSport`.
    case ratioSport
    /// Durée d'application des ratios sport après une séance, en heures.
    case fenetreEffetSport
}

/// Identifie une valeur suivie : le paramètre, et pour `ratioSport` le type
/// de sport concerné (`TypeSport.rawValue`, `nil` pour tous les autres).
struct CleParametre: Hashable, Sendable {
    var parametre: ParametreSuivi
    var typeSport: String? = nil
}

/// Un changement de paramètre de réglage : quand, lequel, de quelle valeur
/// à quelle valeur.
///
/// Prérequis de la frise des périodes (`docs/analyses/C1 — Frise des
/// périodes.md` § 2) : `ProfilUtilisateur` ne garde que la valeur courante,
/// et `DatesChangementRatio` que la date du dernier changement. Sans ces
/// lignes, les valeurs passées sont perdues à chaque modification.
///
/// Écrit uniquement par `ProfilService.mettreAJour`, selon les règles de
/// `HistoriqueParametres` : jamais sur une configuration initiale
/// (`nil → valeur`), et une rafale de saisies au stepper ne produit qu'une
/// seule ligne.
///
/// Contraintes CloudKit du hub : aucun `@Attribute(.unique)`, toute
/// propriété stockée optionnelle ou pourvue d'une valeur par défaut.
@Model
nonisolated final class ChangementParametre {

    var id: UUID = UUID()

    /// Instant où la nouvelle valeur est entrée en vigueur.
    var date: Date = Date.distantPast

    /// `ParametreSuivi.rawValue` — chaîne plutôt qu'enum pour qu'un
    /// paramètre inconnu d'une version future ne fasse pas échouer la
    /// lecture ; il est simplement ignoré (`parametre == nil`).
    var parametreBrut: String = ""

    /// `TypeSport.rawValue` pour `ratioSport`, `nil` sinon.
    var typeSport: String?

    /// `nil` n'arrive que pour une valeur retirée (`nouvelleValeur`) : une
    /// configuration initiale n'est jamais enregistrée.
    var ancienneValeur: Double?
    var nouvelleValeur: Double?

    /// Forme brute — utilisée telle quelle par l'import d'archive, qui doit
    /// pouvoir restituer un paramètre inconnu de cette version.
    init(
        id: UUID = UUID(),
        date: Date,
        parametreBrut: String,
        typeSport: String?,
        ancienneValeur: Double?,
        nouvelleValeur: Double?
    ) {
        self.id = id
        self.date = date
        self.parametreBrut = parametreBrut
        self.typeSport = typeSport
        self.ancienneValeur = ancienneValeur
        self.nouvelleValeur = nouvelleValeur
    }

    convenience init(
        id: UUID = UUID(),
        date: Date,
        cle: CleParametre,
        ancienneValeur: Double?,
        nouvelleValeur: Double?
    ) {
        self.init(
            id: id,
            date: date,
            parametreBrut: cle.parametre.rawValue,
            typeSport: cle.typeSport,
            ancienneValeur: ancienneValeur,
            nouvelleValeur: nouvelleValeur
        )
    }

    var parametre: ParametreSuivi? { ParametreSuivi(rawValue: parametreBrut) }

    var cle: CleParametre? {
        parametre.map { CleParametre(parametre: $0, typeSport: typeSport) }
    }
}
