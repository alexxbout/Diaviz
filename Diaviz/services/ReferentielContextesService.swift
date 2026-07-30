//
//  ReferentielContextesService.swift
//  diaviz
//

import Foundation
import FoundationModels

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
/// Persisté en JSON dans UserDefaults, pas dans le hub SwiftData : ce n'est
/// pas un fait brut horodaté mais un référentiel de catégorisation, à
/// l'échelle de quelques dizaines d'entrées pour un usage personnel — même
/// classe de stockage que `AlimentsRecentsService` (snapshots JSON). Limite
/// connue : contrairement au hub, ce référentiel n'est PAS sauvegardé par
/// CloudKit — en cas de perte (réinstall, nouvel iPhone), les
/// `Repas.contexteNormalise` déjà résolus restent affichés tels quels
/// (persistés côté hub), seule la convergence future de nouvelles
/// formulations vers les entrées existantes est perdue (un nouveau doublon
/// serait recréé) — dégradation gracieuse, pas de perte de donnée visible.
@MainActor
@Observable
final class ReferentielContextesService {
    static let shared = ReferentielContextesService()

    private let cleStockage = "referentielContextesNormalises"
    private let limiteVariantesParEntree = 20

    private(set) var entrees: [ContexteNormalise] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: cleStockage),
           let decodees = try? JSONDecoder().decode([ContexteNormalise].self, from: data) {
            entrees = decodees
        }
    }

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

    private func persister() {
        guard let data = try? JSONEncoder().encode(entrees) else { return }
        UserDefaults.standard.set(data, forKey: cleStockage)
    }
}
