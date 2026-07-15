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
    private let limiteRecents = 50

    /// Clés composites des aliments récents, du plus récent au plus ancien.
    private(set) var clesRecentes: [String] = []

    /// Snapshots des produits OFF, indexés par code-barres.
    private var snapshotsOFF: [String: AlimentOFF] = [:]

    private init() {
        charger()
    }

    // MARK: - API

    func marquerUtilise(_ aliment: ResultatRechercheAliment) {
        clesRecentes.removeAll { $0 == aliment.id }
        clesRecentes.insert(aliment.id, at: 0)
        if clesRecentes.count > limiteRecents {
            clesRecentes = Array(clesRecentes.prefix(limiteRecents))
        }
        if case .off(let produit) = aliment {
            snapshotsOFF[produit.code] = produit
        }
        nettoyerSnapshots()
        sauvegarder()
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
        UserDefaults.standard.removeObject(forKey: cleStockageV2)
        UserDefaults.standard.removeObject(forKey: cleSnapshotsOFF)
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

    /// Supprime les snapshots OFF orphelins (produit sorti de la liste MRU).
    private func nettoyerSnapshots() {
        let codesActifs = Set(clesRecentes.compactMap { cle -> String? in
            guard cle.hasPrefix("off:") else { return nil }
            return String(cle.dropFirst("off:".count))
        })
        snapshotsOFF = snapshotsOFF.filter { codesActifs.contains($0.key) }
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
    }

    private func sauvegarder() {
        let defaults = UserDefaults.standard
        defaults.set(clesRecentes, forKey: cleStockageV2)
        if let data = try? JSONEncoder().encode(snapshotsOFF) {
            defaults.set(data, forKey: cleSnapshotsOFF)
        }
    }
}
