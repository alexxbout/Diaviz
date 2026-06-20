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

    init(
        id: UUID = UUID(),
        emoji: String,
        nom: String,
        quantite: Int,
        glucides: Int,
        insuline: Double
    ) {
        self.id = id
        self.emoji = emoji
        self.nom = nom
        self.quantite = quantite
        self.glucides = glucides
        self.insuline = insuline
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

    /// État du pré-calcul de la réponse glycémique. **Dérivation non persistée**
    /// (`@Transient`) : recalculée à la volée depuis le CGM, et `EtatAnalyse`
    /// embarque une courbe non stockable. Renseignée à l'affichage / en preview.
    @Transient var etatAnalyse: EtatAnalyse?

    init(
        id: UUID = UUID(),
        heure: Date,
        aliments: [Aliment],
        etatAnalyse: EtatAnalyse? = nil,
        iobAuDebut: Double? = nil
    ) {
        self.id = id
        self.heure = heure
        self.aliments = aliments
        self.etatAnalyse = etatAnalyse
        self.iobAuDebut = iobAuDebut
    }

    var totalGlucides: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }

    /// Total d'insuline injectée pour le repas, somme des doses par aliment.
    var totalInsuline: Double {
        aliments.reduce(0) { $0 + $1.insuline }
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
