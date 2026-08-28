//
//  ReferentielContextesService.swift
//  diaviz
//

import Foundation
import FoundationModels
import SwiftData

/// Référentiel des contextes de repas normalisés — un « voiture », un
/// « stress boulot »… vers lesquels convergent différentes formulations
/// brutes de `Repas.contexteLibre` au fil du temps.
///
/// Deux niveaux de résolution, jamais mélangés :
/// - `suggestions(pour:)` : matching local instantané (substring, casse
///   insensible) — utilisé en temps réel pendant la frappe, JAMAIS d'appel
///   LLM ici (voir `SectionContexteRepas`).
/// - `resoudre(texte:)` : résolution différée après enregistrement du repas
///   — réutilise `suggestions` en premier (fast path, pas de LLM si déjà
///   connu), sinon appelle Foundation Models via `ContexteNormaliseGenerator`.
///
/// Persisté dans le hub SwiftData (`ContexteNormaliseEnregistre`), donc
/// synchronisé par CloudKit. Ce n'est pas un fait brut horodaté mais un
/// référentiel de catégorisation, à l'échelle de quelques dizaines d'entrées
/// pour un usage personnel — il vit néanmoins dans le hub pour survivre à une
/// réinstallation : le perdre ferait recréer des doublons pour des
/// formulations déjà rattachées, et l'utilisateur n'a aucun moyen de le
/// reconstruire à la main.
@MainActor
@Observable
final class ReferentielContextesService {
    static let shared = ReferentielContextesService()

    private let limiteVariantesParEntree = 20

    private(set) var entrees: [ContexteNormalise] = []

    private var contexte: ModelContext?

    private init() {}

    // MARK: - Matching local (temps réel, aucun appel LLM)

    /// Entrées dont le libellé ou une variante recoupe `texte`, dans les deux
    /// sens (l'un contient l'autre) — matching volontairement permissif pour
    /// un référentiel de quelques dizaines d'entrées. `texte.count < 2`
    /// renvoie toujours `[]` (bruit sur 0-1 caractère).
    func suggestions(pour texte: String) -> [ContexteNormalise] {
        let requete = texte.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard requete.count >= 2 else { return [] }
        return entrees.filter { entree in
            ([entree.libelle] + entree.variantes).contains { candidat in
                let c = candidat.lowercased()
                guard c.count >= 2 else { return false }
                return c.contains(requete) || requete.contains(c)
            }
        }
    }

    // MARK: - Proposition live (frappe, avec appel LLM)

    /// Propose un libellé + emoji pour `texte`, **sans rien persister**.
    ///
    /// Utilisé par `SheetEvenementsRepas` pendant la frappe, après un debounce
    /// et seulement quand `suggestions(pour:)` ne trouve rien : appeler le
    /// modèle pour un texte déjà connu du référentiel ne produirait qu'une
    /// redite plus lente que le matching local.
    ///
    /// Contrairement à `resoudre(texte:)`, rien n'est écrit : l'utilisateur
    /// doit valider la proposition. Une génération qu'il n'accepte pas ne doit
    /// pas polluer le référentiel — c'est la différence entre suggérer et
    /// décider.
    ///
    /// Renvoie aussi l'entrée existante quand le modèle rattache le texte à
    /// une entrée déjà connue que le matching local avait ratée (formulation
    /// trop éloignée, ex. « au volant » → « Voiture »).
    func proposer(texte: String) async -> ContexteNormalise? {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard propre.count >= 2 else { return nil }
        guard SystemLanguageModel.default.availability == .available else { return nil }
        guard let resultat = await ContexteNormaliseGenerator.generer(texte: propre, referentiel: entrees) else {
            return nil
        }

        if let libelleExistant = resultat.libelleExistant,
           let cible = entrees.first(where: { $0.libelle.caseInsensitiveCompare(libelleExistant) == .orderedSame }) {
            return cible
        }

        // Entrée candidate, volontairement pas encore dans `entrees` : elle
        // n'y entrera qu'au moment où l'utilisateur l'ajoute au repas.
        return ContexteNormalise(
            id: UUID(),
            libelle: resultat.nouveauLibelle,
            emoji: resultat.emoji.first.map(String.init) ?? "🏷️",
            variantes: [propre]
        )
    }

    // MARK: - Édition du référentiel

    /// Ajoute une entrée au référentiel si son id n'y est pas déjà, ou attache
    /// simplement la variante si elle y est. Renvoie l'entrée telle qu'elle
    /// vit dans le référentiel après l'opération.
    @discardableResult
    func adopter(_ entree: ContexteNormalise, texteBrut: String? = nil) -> ContexteNormalise {
        if entrees.contains(where: { $0.id == entree.id }) {
            if let texteBrut { attacherVariante(texteBrut, a: entree.id) }
            return entrees.first { $0.id == entree.id } ?? entree
        }
        var nouvelle = entree
        if let texteBrut {
            let propre = texteBrut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nouvelle.variantes.contains(where: { $0.caseInsensitiveCompare(propre) == .orderedSame }) {
                nouvelle.variantes.append(propre)
            }
        }
        entrees.insert(nouvelle, at: 0)
        persister()
        return nouvelle
    }

    /// Retire une entrée du référentiel. Les `EvenementRepas` déjà posés sur
    /// des repas ne sont **pas** touchés : ils portent leur propre libellé et
    /// emoji, donc un repas tagué « Restaurant » le reste même si l'entrée
    /// disparaît des suggestions. Supprimer ici ne réécrit jamais l'historique.
    func supprimer(_ id: UUID) {
        entrees.removeAll { $0.id == id }
        persister()
    }

    /// Renomme une entrée (libellé et/ou emoji) sans toucher à ses variantes.
    func renommer(_ id: UUID, libelle: String, emoji: String) {
        guard let idx = entrees.firstIndex(where: { $0.id == id }) else { return }
        let libellePropre = libelle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !libellePropre.isEmpty else { return }
        entrees[idx].libelle = libellePropre
        entrees[idx].emoji = emoji.first.map(String.init) ?? entrees[idx].emoji
        persister()
    }

    // MARK: - Résolution différée (post-enregistrement, jamais bloquante)

    /// Résout `texte` vers une entrée du référentiel : fast path local si un
    /// match existe déjà, sinon appel Foundation Models comparé à l'ensemble
    /// du référentiel actuel. `nil` seulement si le modèle est indisponible
    /// ou si la génération échoue — dans ce cas l'appelant ne touche à rien
    /// et l'affichage reste sur le texte brut indéfiniment (pas de retry
    /// automatique).
    func resoudre(texte: String) async -> ContexteNormalise? {
        if let meilleure = suggestions(pour: texte).first {
            attacherVariante(texte, a: meilleure.id)
            return entrees.first { $0.id == meilleure.id }
        }

        guard SystemLanguageModel.default.availability == .available else { return nil }
        guard let resultat = await ContexteNormaliseGenerator.generer(texte: texte, referentiel: entrees) else {
            return nil
        }

        // Le modèle recopie un libellé existant → on le résout nous-mêmes
        // par comparaison exacte (casse insensible) contre `entrees`. Une
        // référence hallucinée (libellé qui n'existe pas vraiment) est
        // traitée comme "créer une nouvelle entrée", jamais un crash.
        if let libelleExistant = resultat.libelleExistant,
           let cible = entrees.first(where: { $0.libelle.caseInsensitiveCompare(libelleExistant) == .orderedSame }) {
            attacherVariante(texte, a: cible.id)
            return entrees.first { $0.id == cible.id }
        }

        let emoji = resultat.emoji.first.map(String.init) ?? "🏷️"
        let nouvelle = ContexteNormalise(
            id: UUID(), libelle: resultat.nouveauLibelle, emoji: emoji, variantes: [texte]
        )
        // Insérée en tête plutôt qu'en fin : `entrees` sert aussi de source
        // aux chips de `SectionContexteRepas` (affichées sans filtre), la
        // plus récemment créée/utilisée doit apparaître en premier.
        entrees.insert(nouvelle, at: 0)
        persister()
        return nouvelle
    }

    private func attacherVariante(_ texte: String, a id: UUID) {
        guard let idx = entrees.firstIndex(where: { $0.id == id }) else { return }
        var entree = entrees[idx]
        let normalise = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entree.variantes.contains(where: { $0.caseInsensitiveCompare(normalise) == .orderedSame }) {
            entree.variantes.append(normalise)
            if entree.variantes.count > limiteVariantesParEntree {
                entree.variantes.removeFirst(entree.variantes.count - limiteVariantesParEntree)
            }
        }
        // Remonte l'entrée utilisée en tête (même logique MRU que
        // `ContextesRepasRecentsService`) — les chips de `SectionContexteRepas`
        // affichent `entrees` tel quel, sans tri ni filtre.
        entrees.remove(at: idx)
        entrees.insert(entree, at: 0)
        persister()
    }

    // MARK: - Persistance

    /// Branche le service sur le hub et charge le référentiel. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    /// Recharge depuis le store — appelé après un import CloudKit, pour
    /// récupérer les entrées créées sur un autre appareil.
    func recharger() {
        guard let contexte else { return }
        let lignes = (try? contexte.fetch(
            FetchDescriptor<ContexteNormaliseEnregistre>(sortBy: [SortDescriptor(\.rang)])
        )) ?? []
        entrees = lignes.map {
            ContexteNormalise(
                id: $0.identifiant,
                libelle: $0.libelle,
                emoji: $0.emoji,
                variantes: $0.variantes
            )
        }
    }

    /// Réécrit les lignes à l'image de `entrees`, en réutilisant celles qui
    /// existent déjà (identité stable, donc pas de churn côté CloudKit).
    private func persister() {
        guard let contexte else { return }

        var parId: [UUID: ContexteNormaliseEnregistre] = [:]
        let existantes = (try? contexte.fetch(FetchDescriptor<ContexteNormaliseEnregistre>())) ?? []
        for ligne in existantes {
            if parId[ligne.identifiant] == nil {
                parId[ligne.identifiant] = ligne
            } else {
                // Doublon né d'une fusion CloudKit : une seule ligne par id.
                contexte.delete(ligne)
            }
        }

        for (rang, entree) in entrees.enumerated() {
            if let ligne = parId.removeValue(forKey: entree.id) {
                ligne.libelle = entree.libelle
                ligne.emoji = entree.emoji
                ligne.variantes = entree.variantes
                ligne.rang = rang
            } else {
                contexte.insert(ContexteNormaliseEnregistre(
                    identifiant: entree.id,
                    libelle: entree.libelle,
                    emoji: entree.emoji,
                    variantes: entree.variantes,
                    rang: rang
                ))
            }
        }

        // Suppression objet par objet (jamais en batch) pour que CloudKit
        // exporte réellement le retrait.
        for ligne in parId.values {
            contexte.delete(ligne)
        }

        try? contexte.save()
    }
}
