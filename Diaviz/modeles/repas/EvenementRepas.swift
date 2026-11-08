//
//  EvenementRepas.swift
//  diaviz
//

import Foundation

/// Un événement de vie attaché à un repas — « 🚘 Voiture », « 🍽️ Restaurant ».
///
/// Remplace le `Repas.contexteLibre` unique : un même repas peut cumuler
/// plusieurs circonstances (au restaurant **et** stressé), qu'un seul champ
/// texte ne savait pas représenter.
///
/// `idReferentiel` pointe vers l'entrée de `ReferentielContextesService` dont
/// cet événement est issu, quand il en vient une — c'est ce qui permet de
/// renommer une entrée du référentiel et de voir le changement se propager.
/// `nil` pour un événement saisi librement et jamais rattaché (modèle
/// on-device indisponible au moment de la saisie, par exemple).
///
/// `texteBrut` conserve ce que l'utilisateur a réellement tapé, même une fois
/// le libellé normalisé : c'est la matière première des `variantes` du
/// référentiel, et la seule trace de sa formulation d'origine.
nonisolated struct EvenementRepas: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var idReferentiel: UUID?
    var libelle: String
    var emoji: String
    var texteBrut: String?

    init(
        id: UUID = UUID(),
        idReferentiel: UUID? = nil,
        libelle: String,
        emoji: String,
        texteBrut: String? = nil
    ) {
        self.id = id
        self.idReferentiel = idReferentiel
        self.libelle = libelle
        self.emoji = emoji
        self.texteBrut = texteBrut
    }

    /// Emoji + libellé **tels que stockés sur cet événement** — figés à
    /// l'ajout, ne suivent pas un renommage ultérieur de l'entrée du
    /// référentiel. Utiliser `affichage` seulement pour un événement qu'on
    /// sait détaché du référentiel (`idReferentiel == nil`) ; partout ailleurs
    /// préférer `affichageResolu`. L'emoji peut manquer sur un événement
    /// reconstruit depuis un ancien `contexteLibre` (voir
    /// `Repas.evenementsAffiches`) — on n'affiche alors pas d'espace orphelin
    /// en tête.
    var affichage: String {
        emoji.isEmpty ? libelle : "\(emoji) \(libelle)"
    }

    /// Emoji + libellé **résolus depuis le référentiel courant** quand
    /// `idReferentiel` pointe vers une entrée encore présente — sinon replie
    /// sur `affichage`. Point d'injection unique du renommage : un événement
    /// stocke une copie figée du libellé/emoji au moment de l'ajout (comme
    /// `AlimentCiqual.nom` figé dans un `Aliment` du hub), donc sans cette
    /// résolution un renommage dans `SheetEvenementsRepas` ne se
    /// propagerait à aucun badge déjà posé sur un repas.
    @MainActor
    var affichageResolu: String {
        guard let idReferentiel,
              let entree = ReferentielContextesService.shared.entrees.first(where: { $0.id == idReferentiel })
        else { return affichage }
        return entree.affichage
    }

    /// Construit un événement depuis une entrée du référentiel.
    init(depuis entree: ContexteNormalise, texteBrut: String? = nil) {
        self.init(
            idReferentiel: entree.id,
            libelle: entree.libelle,
            emoji: entree.emoji,
            texteBrut: texteBrut
        )
    }
}
