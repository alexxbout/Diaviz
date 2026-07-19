//
//  Aliment.swift
//  diaviz
//
//  Created by Alexandre on 22/04/2026.
//

import Foundation
import SwiftData

/// Un aliment d'un repas, tel qu'enregistré dans le hub : forme déjà résolue
/// (emoji / nom / glucides / dose). Distinct de `EntreeAliment` (saisie, lié à
/// `AlimentCiqual`) et de `AlimentCiqual` (référentiel, hors hub).
@Model
final class Aliment {
    var id: UUID
    var emoji: String
    var nom: String
    var quantite: Int
    var glucides: Int
    var insuline: Double
    /// Photo du produit (Open Food Facts) — `nil` pour un aliment CIQUAL ou
    /// les repas antérieurs à l'ajout du champ (migration légère).
    var imageURL: URL?
    /// Pris pour traiter une hypoglycémie (resucrage) plutôt qu'un aliment de
    /// repas ordinaire. `false` par défaut (migration légère des repas
    /// antérieurs à l'ajout du champ).
    var resucrage: Bool = false

    init(
        id: UUID = UUID(),
        emoji: String,
        nom: String,
        quantite: Int,
        glucides: Int,
        insuline: Double,
        imageURL: URL? = nil,
        resucrage: Bool = false
    ) {
        self.id = id
        self.emoji = emoji
        self.nom = nom
        self.quantite = quantite
        self.glucides = glucides
        self.insuline = insuline
        self.imageURL = imageURL
        self.resucrage = resucrage
    }
}

/// Un repas enregistré dans le hub. **Fait brut horodaté** (`@Model`) : `heure`
/// absolue + liste d'aliments. La réponse glycémique (`etatAnalyse`) est une
/// **dérivation** calculée depuis le CGM — jamais persistée, d'où `@Transient`.
@Model
final class Repas {
    var id: UUID
    /// Horodatage absolu du repas (clé de tri / découpage).
    var heure: Date

    /// Aliments du repas. Relation cascade : supprimer le repas supprime ses
    /// aliments (ils n'existent pas hors d'un repas).
    @Relationship(deleteRule: .cascade) var aliments: [Aliment]

    /// Insuline rapide encore active au démarrage du repas (unités). Snapshot
    /// figé à la saisie ; `nil` si non calculé (legacy ou pas de bolus récent).
    var iobAuDebut: Double?

    /// Dose unique saisie pour l'ensemble du repas (mode « dose globale »),
    /// quand l'utilisateur connaît les quantités mais ne veut pas ventiler la
    /// dose aliment par aliment. `nil` = mode classique (dose par aliment) —
    /// la valeur EST le flag, pas de booléen séparé à désynchroniser. Dans ce
    /// mode les `Aliment.insuline` valent 0 (pas d'attribution par aliment).
    var doseGlobale: Double?

    /// État du pré-calcul de la réponse glycémique. **Dérivation non persistée**
    /// (`@Transient`) : recalculée à la volée depuis le CGM, et `EtatAnalyse`
    /// embarque une courbe non stockable. Renseignée à l'affichage / en preview.
    @Transient var etatAnalyse: EtatAnalyse?

    init(
        id: UUID = UUID(),
        heure: Date,
        aliments: [Aliment],
        etatAnalyse: EtatAnalyse? = nil,
        iobAuDebut: Double? = nil,
        doseGlobale: Double? = nil
    ) {
        self.id = id
        self.heure = heure
        self.aliments = aliments
        self.etatAnalyse = etatAnalyse
        self.iobAuDebut = iobAuDebut
        self.doseGlobale = doseGlobale
    }

    var totalGlucides: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }

    /// Total d'insuline du repas : la dose globale quand le repas a été saisi
    /// dans ce mode, sinon la somme des doses par aliment. Tout l'affichage
    /// (journal, détail, ratio) passe par ici et suit automatiquement.
    var totalInsuline: Double {
        doseGlobale ?? aliments.reduce(0) { $0 + $1.insuline }
    }

    /// Indique si au moins un aliment a une dose d'insuline associée. Sert à
    /// différencier un repas "logué pour mémoire" d'un repas avec bolus.
    var aUneInjection: Bool {
        totalInsuline > 0
    }

    /// Emoji représentatif du repas : l'aliment le plus contributeur en
    /// glucides (il pilote la réponse glycémique). À défaut, un emoji générique.
    var emojiPrincipal: String {
        aliments.max(by: { $0.glucides < $1.glucides })?.emoji ?? "🍽"
    }
}
