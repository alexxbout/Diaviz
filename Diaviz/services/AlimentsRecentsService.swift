//
//  AlimentsRecentsService.swift
//  diaviz
//
//  Created by Alexandre on 27/04/2026.
//

import Foundation

/// Historique MRU des aliments utilisés, toutes sources confondues (CIQUAL et
/// Open Food Facts), persisté dans UserDefaults.
///
/// Clés composites `"ciqual:123"` / `"off:3017620422003"` (voir
/// `ResultatRechercheAliment.id`). Les aliments CIQUAL sont résolus à la volée
/// depuis la base locale ; les produits OFF n'ont pas de base locale, donc un
/// **snapshot JSON** du produit est conservé au moment de l'utilisation.
///
/// Migration douce : l'ancien stockage (`"alimentsRecents"`, `[Int]` CIQUAL)
/// est converti vers le format composite au premier lancement, sans être
/// supprimé (rollback possible vers une version antérieure de l'app).
@Observable
final class AlimentsRecentsService {
    static let shared = AlimentsRecentsService()

    /// Ancien stockage V1 — `[Int]` d'ids CIQUAL. Lu pour migration uniquement.
    private let cleStockageV1 = "alimentsRecents"
    /// Stockage courant — `[String]` de clés composites, ordre MRU.
    private let cleStockageV2 = "alimentsRecentsV2"
    /// Snapshots des produits OFF récents — `[code: JSON(AlimentOFF)]`.
    private let cleSnapshotsOFF = "alimentsRecentsSnapshotsOFF"
    /// Dernière quantité saisie par aliment — `[cléComposite: grammes]`.
    private let cleQuantites = "alimentsRecentsQuantites"
    /// Taille d'une portion définie par l'utilisateur — `[cléComposite: grammes]`.
    private let cleTaillesPortion = "alimentsRecentsTaillesPortion"
    /// Dernier mode de saisie utilisé — `[cléComposite: "grammes"|"portions"]`.
    private let cleModesQuantite = "alimentsRecentsModesQuantite"
    private let limiteRecents = 50

    /// Clés composites des aliments récents, du plus récent au plus ancien.
    private(set) var clesRecentes: [String] = []

    /// Snapshots des produits OFF, indexés par code-barres.
    private var snapshotsOFF: [String: AlimentOFF] = [:]

    /// Dernière quantité (grammes) utilisée pour chaque aliment. Une portion
    /// est très stable d'un repas à l'autre (le même yaourt, le même bol de
    /// pâtes) — la repropose évite de re-régler le slider à chaque fois.
    private var quantites: [String: Double] = [:]

    /// Taille (grammes) d'une portion, définie par l'utilisateur pour cet
    /// aliment. Absente tant qu'il n'a jamais activé le mode « Portions »
    /// pour lui.
    private var taillesPortion: [String: Double] = [:]

    /// Dernier mode de saisie (grammes ou portions) utilisé pour cet
    /// aliment — repropose le même mode la prochaine fois.
    private var modesQuantite: [String: ModeQuantiteAliment] = [:]

    private init() {
        charger()
    }

    // MARK: - API

    /// Marque un aliment comme utilisé. `quantite` (grammes) est mémorisée
    /// pour préremplir la prochaine saisie du même aliment — passer `nil` la
    /// laisse inchangée plutôt que de l'effacer.
    func marquerUtilise(
        _ aliment: ResultatRechercheAliment,
        quantite: Double? = nil,
        modeQuantite: ModeQuantiteAliment? = nil
    ) {
        clesRecentes.removeAll { $0 == aliment.id }
        clesRecentes.insert(aliment.id, at: 0)
        if clesRecentes.count > limiteRecents {
            clesRecentes = Array(clesRecentes.prefix(limiteRecents))
        }
        if case .off(let produit) = aliment {
            snapshotsOFF[produit.code] = produit
        }
        if let quantite, quantite > 0 {
            quantites[aliment.id] = quantite
        }
        if let modeQuantite {
            modesQuantite[aliment.id] = modeQuantite
        }
        nettoyerSnapshots()
        sauvegarder()
    }

    /// Dernière quantité (grammes) saisie pour cet aliment, `nil` s'il n'a
    /// jamais été enregistré dans un repas validé.
    func derniereQuantite(_ aliment: ResultatRechercheAliment) -> Double? {
        quantites[aliment.id]
    }

    /// Taille (grammes) d'une portion pour cet aliment, `nil` si jamais
    /// définie — le mode « Portions » propose alors de la définir.
    func tailleDePortion(_ aliment: ResultatRechercheAliment) -> Double? {
        taillesPortion[aliment.id]
    }

    /// Définit (ou redéfinit) la taille d'une portion pour cet aliment.
    /// Persisté immédiatement, indépendamment de la validation du repas en
    /// cours — c'est une définition durable, pas un réglage de saisie.
    func definirTailleDePortion(_ aliment: ResultatRechercheAliment, grammes: Double) {
        guard grammes > 0 else { return }
        taillesPortion[aliment.id] = grammes
        sauvegarder()
    }

    /// Dernier mode de saisie utilisé pour cet aliment, `.grammes` par
    /// défaut pour un aliment jamais enregistré.
    func dernierMode(_ aliment: ResultatRechercheAliment) -> ModeQuantiteAliment {
        modesQuantite[aliment.id] ?? .grammes
    }

    func estRecent(_ aliment: ResultatRechercheAliment) -> Bool {
        clesRecentes.contains(aliment.id)
    }

    /// Position MRU (0 = le plus récent), `nil` si absent. Sert au boost de
    /// pertinence de la recherche CIQUAL.
    func position(_ aliment: ResultatRechercheAliment) -> Int? {
        clesRecentes.firstIndex(of: aliment.id)
    }

    /// Aliments récents résolus, ordre MRU. Une clé irrésoluble (aliment
    /// disparu de la base CIQUAL, snapshot OFF manquant) est ignorée, de même
    /// qu'un aliment CIQUAL masqué par l'utilisateur.
    var alimentsRecents: [ResultatRechercheAliment] {
        clesRecentes.compactMap { resoudre(cle: $0) }
            .filter { aliment in
                guard case .ciqual(let a) = aliment else { return true }
                return !AlimentsCachesService.shared.estCache(a.id)
            }
    }

    func effacer() {
        clesRecentes = []
        snapshotsOFF = [:]
        quantites = [:]
        taillesPortion = [:]
        modesQuantite = [:]
        UserDefaults.standard.removeObject(forKey: cleStockageV2)
        UserDefaults.standard.removeObject(forKey: cleSnapshotsOFF)
        UserDefaults.standard.removeObject(forKey: cleQuantites)
        UserDefaults.standard.removeObject(forKey: cleTaillesPortion)
        UserDefaults.standard.removeObject(forKey: cleModesQuantite)
        UserDefaults.standard.removeObject(forKey: cleStockageV1)
    }

    // MARK: - Résolution

    private func resoudre(cle: String) -> ResultatRechercheAliment? {
        if let idCiqual = Self.idCiqual(depuis: cle) {
            guard let aliment = CiqualService.shared.aliments.first(where: { $0.id == idCiqual }) else {
                return nil
            }
            return .ciqual(aliment)
        }
        if cle.hasPrefix("off:") {
            let code = String(cle.dropFirst("off:".count))
            guard let produit = snapshotsOFF[code] else { return nil }
            return .off(produit)
        }
        return nil
    }

    private static func idCiqual(depuis cle: String) -> Int? {
        guard cle.hasPrefix("ciqual:") else { return nil }
        return Int(cle.dropFirst("ciqual:".count))
    }

    /// Supprime les snapshots OFF et les quantités orphelins (aliment sorti
    /// de la liste MRU) — sans ça, les deux dictionnaires grossiraient
    /// indéfiniment alors que la liste MRU, elle, est plafonnée.
    private func nettoyerSnapshots() {
        let codesActifs = Set(clesRecentes.compactMap { cle -> String? in
            guard cle.hasPrefix("off:") else { return nil }
            return String(cle.dropFirst("off:".count))
        })
        snapshotsOFF = snapshotsOFF.filter { codesActifs.contains($0.key) }

        let clesActives = Set(clesRecentes)
        quantites = quantites.filter { clesActives.contains($0.key) }
    }

    // MARK: - Persistance

    private func charger() {
        let defaults = UserDefaults.standard

        if let v2 = defaults.array(forKey: cleStockageV2) as? [String] {
            clesRecentes = v2
        } else if let v1 = defaults.array(forKey: cleStockageV1) as? [Int] {
            // Migration V1 → V2 : les anciens récents étaient tous CIQUAL.
            // L'ancienne clé est conservée telle quelle (rollback possible).
            clesRecentes = v1.map { "ciqual:\($0)" }
            defaults.set(clesRecentes, forKey: cleStockageV2)
        }

        if let data = defaults.data(forKey: cleSnapshotsOFF),
           let snapshots = try? JSONDecoder().decode([String: AlimentOFF].self, from: data) {
            snapshotsOFF = snapshots
        }

        if let stockees = defaults.dictionary(forKey: cleQuantites) as? [String: Double] {
            quantites = stockees
        }

        if let stockees = defaults.dictionary(forKey: cleTaillesPortion) as? [String: Double] {
            taillesPortion = stockees
        }

        if let stockes = defaults.dictionary(forKey: cleModesQuantite) as? [String: String] {
            modesQuantite = stockes.compactMapValues(ModeQuantiteAliment.init(rawValue:))
        }
    }

    private func sauvegarder() {
        let defaults = UserDefaults.standard
        defaults.set(clesRecentes, forKey: cleStockageV2)
        if let data = try? JSONEncoder().encode(snapshotsOFF) {
            defaults.set(data, forKey: cleSnapshotsOFF)
        }
        defaults.set(quantites, forKey: cleQuantites)
        defaults.set(taillesPortion, forKey: cleTaillesPortion)
        defaults.set(modesQuantite.mapValues(\.rawValue), forKey: cleModesQuantite)
    }
}
