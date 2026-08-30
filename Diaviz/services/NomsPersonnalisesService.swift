//
//  NomsPersonnalisesService.swift
//  diaviz
//

import Foundation
import SwiftData

/// Personnalisation utilisateur des aliments CIQUAL — nom et emoji — avec
/// restauration possible de la valeur d'origine. Le référentiel CIQUAL
/// (`ciqual.json`) est statique et rechargé à l'identique à chaque
/// lancement — la personnalisation vit donc dans une couche séparée,
/// indexée par `AlimentCiqual.id`, sur le même pattern que
/// `AlimentsCachesService`.
///
/// Réservé à CIQUAL : les produits Open Food Facts ont déjà un nom +
/// marque propres au produit scanné, pas de référentiel générique à
/// personnaliser.
///
/// N'affecte que la recherche et la saisie en cours (voir
/// `ResultatRechercheAliment.nom`/`.emoji`, points d'injection uniques) —
/// les repas déjà enregistrés ont leur nom figé dans le modèle SwiftData
/// `Aliment` au moment de l'ajout, une personnalisation ultérieure ne les
/// modifie pas.
///
/// Persisté dans le hub SwiftData (`PreferenceAlimentCiqual`), donc
/// synchronisé par CloudKit — un renommage survit à une réinstallation.
/// L'état reste tenu en mémoire pour la lecture (appelée sur chaque ligne de
/// résultat de recherche), le store n'étant touché qu'à l'écriture.
@Observable
final class NomsPersonnalisesService {
    static let shared = NomsPersonnalisesService()

    /// Noms personnalisés, indexés par id CIQUAL.
    private(set) var noms: [Int: String] = [:]

    /// Emojis personnalisés, indexés par id CIQUAL.
    private(set) var emojis: [Int: String] = [:]

    private var contexte: ModelContext?

    private init() {}

    /// Branche le service sur le hub et charge l'état. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    /// Recharge depuis le store — appelé après un import CloudKit, pour que
    /// des personnalisations arrivées d'un autre appareil soient prises en
    /// compte sans redémarrage.
    func recharger() {
        guard let contexte else { return }
        let lignes = (try? contexte.fetch(FetchDescriptor<PreferenceAlimentCiqual>())) ?? []
        noms = [:]
        emojis = [:]
        for ligne in lignes {
            if let nom = ligne.nomPersonnalise { noms[ligne.idCiqual] = nom }
            if let emoji = ligne.emojiPersonnalise { emojis[ligne.idCiqual] = emoji }
        }
    }

    // MARK: - Nom

    func renommer(_ id: Int, en nom: String) {
        let nom = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nom.isEmpty else { return }
        let ancien = noms[id]
        noms[id] = nom
        PreferencesAlimentsStockage.modifier(id, contexte: contexte) { $0.nomPersonnalise = nom }
        // Préférence persistante posée sans aucun accusé de réception : la
        // sheet se ferme et seul le prochain résultat de recherche la révèle.
        ToastsService.shared.afficher(.reglage, titre: "Aliment renommé", detail: nom, action: ActionToast(libelle: "Annuler") { [weak self] in
            guard let self else { return }
            if let ancien { self.renommer(id, en: ancien) } else { self.restaurerNom(id) }
        })
    }

    func restaurerNom(_ id: Int) {
        noms.removeValue(forKey: id)
        PreferencesAlimentsStockage.modifier(id, contexte: contexte) { $0.nomPersonnalise = nil }
    }

    func nomPersonnalise(pour id: Int) -> String? {
        noms[id]
    }

    /// Nom à afficher pour cet aliment CIQUAL — personnalisé s'il existe,
    /// sinon le nom d'origine.
    func nom(pour aliment: AlimentCiqual) -> String {
        noms[aliment.id] ?? aliment.nom
    }

    // MARK: - Emoji

    func changerEmoji(_ id: Int, en emoji: String) {
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emoji.isEmpty else { return }
        let ancien = emojis[id]
        emojis[id] = emoji
        PreferencesAlimentsStockage.modifier(id, contexte: contexte) { $0.emojiPersonnalise = emoji }
        ToastsService.shared.afficher(.reglage, titre: "Emoji modifié", detail: emoji, action: ActionToast(libelle: "Annuler") { [weak self] in
            guard let self else { return }
            if let ancien { self.changerEmoji(id, en: ancien) } else { self.restaurerEmoji(id) }
        })
    }

    func restaurerEmoji(_ id: Int) {
        emojis.removeValue(forKey: id)
        PreferencesAlimentsStockage.modifier(id, contexte: contexte) { $0.emojiPersonnalise = nil }
    }

    func emojiPersonnalise(pour id: Int) -> String? {
        emojis[id]
    }

    /// Emoji à afficher pour cet aliment CIQUAL — personnalisé s'il existe,
    /// sinon l'emoji d'origine (potentiellement absent côté CIQUAL).
    func emoji(pour aliment: AlimentCiqual) -> String? {
        emojis[aliment.id] ?? aliment.emoji
    }

    // MARK: - Liste

    /// Aliments CIQUAL personnalisés (nom et/ou emoji), résolus depuis le
    /// référentiel courant, triés par nom affiché.
    var alimentsPersonnalises: [AlimentCiqual] {
        CiqualService.shared.aliments
            .filter { noms[$0.id] != nil || emojis[$0.id] != nil }
            .sorted { nom(pour: $0) < nom(pour: $1) }
    }

    // MARK: - Rattrapage des repas antérieurs

    /// Index inverse « nom CIQUAL d'origine → id », restreint aux seuls
    /// aliments personnalisés (donc quelques entrées, pas les ~3000 du
    /// référentiel).
    ///
    /// Sert à retrouver l'id CIQUAL d'un `Aliment` du hub enregistré **avant**
    /// l'ajout de `Aliment.idCiqualSource` : son `nom` figé est alors
    /// forcément le nom CIQUAL d'origine (la personnalisation n'existait pas
    /// encore). Sans ça, un renommage ne remonterait que sur les repas
    /// enregistrés après coup.
    private var idsParNomOrigine: [String: Int] {
        var index: [String: Int] = [:]
        for aliment in alimentsPersonnalises {
            index[aliment.nom] = aliment.id
        }
        return index
    }

    /// Id CIQUAL d'un aliment personnalisé portant exactement ce nom
    /// d'origine, `nil` si aucun. Volontairement une correspondance stricte :
    /// approximer risquerait de renommer un aliment que l'utilisateur n'a
    /// jamais touché.
    func idCiqual(pourNomOrigine nom: String) -> Int? {
        idsParNomOrigine[nom]
    }
}

// MARK: - Stockage partagé des préférences par aliment CIQUAL

/// Accès à `PreferenceAlimentCiqual`, partagé entre
/// `NomsPersonnalisesService` et `AlimentsCachesService` : les deux écrivent
/// des champs différents de la **même** ligne, une par aliment.
enum PreferencesAlimentsStockage {

    /// Modifie (ou crée) la ligne d'un aliment, puis la supprime si elle ne
    /// porte plus aucun réglage — inutile de faire voyager sur iCloud des
    /// lignes neutres nées d'un renommage annulé.
    @MainActor
    static func modifier(
        _ idCiqual: Int,
        contexte: ModelContext?,
        _ modification: (PreferenceAlimentCiqual) -> Void
    ) {
        guard let contexte else { return }

        let ligne: PreferenceAlimentCiqual
        if let existante = chercher(idCiqual, contexte: contexte) {
            ligne = existante
        } else {
            ligne = PreferenceAlimentCiqual(idCiqual: idCiqual)
            contexte.insert(ligne)
        }

        modification(ligne)

        if ligne.estVide {
            contexte.delete(ligne)
        }
        try? contexte.save()
    }

    @MainActor
    static func chercher(_ idCiqual: Int, contexte: ModelContext) -> PreferenceAlimentCiqual? {
        var descripteur = FetchDescriptor<PreferenceAlimentCiqual>(
            predicate: #Predicate { $0.idCiqual == idCiqual }
        )
        descripteur.fetchLimit = 1
        return (try? contexte.fetch(descripteur))?.first
    }
}
