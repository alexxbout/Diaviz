//
//  NomsPersonnalisesService.swift
//  diaviz
//

import Foundation

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
@Observable
final class NomsPersonnalisesService {
    static let shared = NomsPersonnalisesService()

    private let cleStockageNoms = "nomsPersonnalisesCiqual"
    private let cleStockageEmojis = "emojisPersonnalisesCiqual"

    /// Noms personnalisés, indexés par id CIQUAL.
    private(set) var noms: [Int: String] = [:]

    /// Emojis personnalisés, indexés par id CIQUAL.
    private(set) var emojis: [Int: String] = [:]

    private init() {
        charger()
    }

    // MARK: - Nom

    func renommer(_ id: Int, en nom: String) {
        let nom = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nom.isEmpty else { return }
        noms[id] = nom
        sauvegarder()
    }

    func restaurerNom(_ id: Int) {
        noms.removeValue(forKey: id)
        sauvegarder()
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
        emojis[id] = emoji
        sauvegarder()
    }

    func restaurerEmoji(_ id: Int) {
        emojis.removeValue(forKey: id)
        sauvegarder()
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

    // MARK: - Persistance

    private func charger() {
        if let stockes = UserDefaults.standard.dictionary(forKey: cleStockageNoms) as? [String: String] {
            noms = Dictionary(uniqueKeysWithValues: stockes.compactMap { cle, valeur in
                Int(cle).map { ($0, valeur) }
            })
        }
        if let stockes = UserDefaults.standard.dictionary(forKey: cleStockageEmojis) as? [String: String] {
            emojis = Dictionary(uniqueKeysWithValues: stockes.compactMap { cle, valeur in
                Int(cle).map { ($0, valeur) }
            })
        }
    }

    private func sauvegarder() {
        let nomsStockes = Dictionary(uniqueKeysWithValues: noms.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(nomsStockes, forKey: cleStockageNoms)
        let emojisStockes = Dictionary(uniqueKeysWithValues: emojis.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(emojisStockes, forKey: cleStockageEmojis)
    }
}
