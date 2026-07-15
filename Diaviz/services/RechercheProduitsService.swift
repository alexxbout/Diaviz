//
//  RechercheProduitsService.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import Foundation
import Observation

/// État de la recherche de produits Open Food Facts pour l'onglet « Produits »
/// de la saisie de repas.
///
/// Stratégie d'appels réseau (quota OFF : 10 recherches/min/IP) :
/// - Déclenchement **explicite** uniquement : bouton « rechercher » du clavier
///   iOS, ou bascule vers l'onglet Produits avec un texte déjà saisi. Jamais
///   à la frappe (contrairement à la recherche CIQUAL locale).
/// - **Cache session** terme normalisé → résultats : re-basculer d'onglet ou
///   relancer la même recherche ne re-frappe pas l'API.
/// - Une nouvelle recherche annule la précédente encore en vol.
@Observable
@MainActor
final class RechercheProduitsService {

    /// Résultats de la dernière recherche aboutie.
    private(set) var resultats: [AlimentOFF] = []
    /// Vrai pendant un appel réseau.
    private(set) var enChargement = false
    /// Erreur de la dernière recherche, `nil` si succès.
    private(set) var erreur: OFFError?
    /// Terme (normalisé) correspondant aux `resultats` affichés. Vide tant
    /// qu'aucune recherche n'a été lancée.
    private(set) var termeAffiche = ""
    /// Vrai si des pages supplémentaires existent pour le terme affiché.
    private(set) var peutChargerPlus = false
    /// Vrai pendant le chargement d'une page supplémentaire (le bouton
    /// « Afficher plus » devient un spinner, la liste reste en place).
    private(set) var chargementPagePlus = false

    /// État complet d'un terme déjà recherché (résultats cumulés + pagination).
    private struct EntreeCache {
        var produits: [AlimentOFF]
        var dernierePage: Int
        var nombreDePages: Int
    }

    private var cache: [String: EntreeCache] = [:]
    private var tacheEnCours: Task<Void, Never>?
    private let client: OpenFoodFactsAPIClient

    init(client: OpenFoodFactsAPIClient = .shared) {
        self.client = client
    }

    /// Lance une recherche si nécessaire. No-op si le terme est trop court ou
    /// identique à celui déjà affiché ; réponse immédiate si le terme est en
    /// cache (aucun appel réseau).
    func rechercher(_ terme: String) {
        let termeNormalise = terme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard termeNormalise.count >= 2 else { return }
        // Même terme déjà affiché sans erreur → rien à faire (couvre les
        // allers-retours d'onglets sans changement de texte).
        if termeNormalise == termeAffiche && erreur == nil { return }

        if let enCache = cache[termeNormalise] {
            tacheEnCours?.cancel()
            afficher(enCache, terme: termeNormalise)
            enChargement = false
            chargementPagePlus = false
            return
        }

        tacheEnCours?.cancel()
        tacheEnCours = Task {
            enChargement = true
            erreur = nil
            do {
                let page = try await client.rechercher(termeNormalise)
                guard !Task.isCancelled else { return }
                let entree = EntreeCache(
                    produits: page.produits,
                    dernierePage: page.page,
                    nombreDePages: page.nombreDePages
                )
                cache[termeNormalise] = entree
                afficher(entree, terme: termeNormalise)
            } catch let e as OFFError {
                guard !Task.isCancelled else { return }
                erreur = e
                termeAffiche = termeNormalise
                peutChargerPlus = false
            } catch {
                // `client.rechercher` ne jette que des OFFError.
            }
            enChargement = false
        }
    }

    /// Charge la page suivante du terme affiché et l'ajoute aux résultats.
    /// No-op si tout est déjà chargé ou si un chargement est en cours.
    func chargerPlus() {
        let terme = termeAffiche
        guard peutChargerPlus, !chargementPagePlus, !enChargement,
              var entree = cache[terme] else { return }

        tacheEnCours?.cancel()
        tacheEnCours = Task {
            chargementPagePlus = true
            do {
                let page = try await client.rechercher(terme, page: entree.dernierePage + 1)
                guard !Task.isCancelled else { return }
                // Dédoublonne au cas où le classement bouge entre deux pages.
                let connus = Set(entree.produits.map(\.code))
                entree.produits += page.produits.filter { !connus.contains($0.code) }
                entree.dernierePage = page.page
                entree.nombreDePages = page.nombreDePages
                cache[terme] = entree
                afficher(entree, terme: terme)
            } catch let e as OFFError {
                guard !Task.isCancelled else { return }
                // Échec d'une page « plus » : on garde les résultats affichés,
                // seul le bouton signale l'erreur au prochain tap.
                erreur = e
            } catch {
                // `client.rechercher` ne jette que des OFFError.
            }
            chargementPagePlus = false
        }
    }

    /// Pousse un état de cache vers les propriétés affichées.
    private func afficher(_ entree: EntreeCache, terme: String) {
        resultats = entree.produits
        termeAffiche = terme
        erreur = nil
        peutChargerPlus = entree.dernierePage < entree.nombreDePages
    }

    /// Oublie l'état affiché (texte de recherche effacé). Le cache session
    /// est conservé : retaper la même recherche reste instantané.
    func reinitialiserAffichage() {
        tacheEnCours?.cancel()
        resultats = []
        termeAffiche = ""
        erreur = nil
        enChargement = false
        peutChargerPlus = false
        chargementPagePlus = false
    }
}
