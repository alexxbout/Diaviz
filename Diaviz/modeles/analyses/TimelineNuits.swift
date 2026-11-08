//
//  TimelineNuits.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation

// MARK: - Timeline des nuits

/// Raison textuelle d'exclusion d'une nuit — affichée en popover quand
/// l'utilisateur tape un point gris dans la timeline. Format court qui
/// rentre sur une ligne (`.caption .secondary`).
nonisolated enum RaisonExclusion: String, Sendable, Equatable {
    case iobResiduel = "IOB résiduel"
    case sportTardif = "Sport tardif"
    case repasCopieux = "Repas tardif copieux"
    case resucrage = "Resucrage en nuit profonde"
    /// La zone démarre pendant la retombée d'un rebond post-hypo — la
    /// glycémie redescend de son dépassement, pas de la basale.
    case rebondPostHypo = "Rebond post-hypo"
    case cgmIncomplet = "Couverture CGM insuffisante"
    case bolusCorrection = "Correction au coucher"
    /// Rapide non-correctif (repas, collation) dans la zone, sous le seuil
    /// « repas copieux » — trop petit pour `repasCopieux`, mais l'insuline
    /// et les glucides absorbés faussent quand même la pente basale.
    case bolusNonCorrectif = "Insuline hors basale"
    case chaotique = "Glycémie instable"
    case modePause = "Mode pause"
    case pasDeLente = "Lente non renseignée"
    case dureeInsuffisante = "Fenêtre trop courte"
    case classementManuel = "Écartée par vous"
}

/// État visuel d'une nuit dans la timeline 14 jours.
///
/// L'analyse V1 traite chaque nuit comme un tout — soit on l'inclut
/// (`.valide`), soit on l'exclut (`.exclue` avec raison). Une V2
/// pourrait analyser des **portions** de nuit (par ex. inclure la
/// fenêtre 02h-06h même si une correction a eu lieu à 23h), mais cette
/// granularité ajouterait une couche de logique non-triviale sur le
/// pipeline ML — repoussée volontairement à plus tard.
nonisolated enum EtatNuit: Sendable, Equatable {
    case valide(categorie: CategorieNuit)
    case exclue(raison: RaisonExclusion)
    case sansDonnees
    case enCours

    static func == (lhs: EtatNuit, rhs: EtatNuit) -> Bool {
        switch (lhs, rhs) {
        case (.valide(let a), .valide(let b)):  return a == b
        case (.exclue(let a), .exclue(let b)):  return a == b
        case (.sansDonnees, .sansDonnees):      return true
        case (.enCours, .enCours):              return true
        default:                                return false
        }
    }

    /// `true` si la nuit a été incluse dans le calcul — pilote la
    /// couleur du point et la ligne verte de connexion.
    var estValide: Bool {
        if case .valide = self { return true }
        return false
    }
}

nonisolated extension CategorieNuit: Equatable {}

/// Une cellule de la timeline 14 jours.
///
/// Le drapeau `avantChangementDose` permet de griser visuellement les
/// nuits qui précèdent un changement de dose récent : leur glycémie
/// reflète l'ancien réglage et ne devrait pas être moyennée avec les
/// nuits post-changement.
nonisolated struct NuitTimeline: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let etat: EtatNuit
    let avantChangementDose: Bool
}
