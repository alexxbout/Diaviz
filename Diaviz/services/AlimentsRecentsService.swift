//
//  AlimentsRecentsService.swift
//  diaviz
//
//  Created by Alexandre on 27/04/2026.
//

import Foundation
import SwiftData

/// Historique MRU des aliments utilisés, toutes sources confondues (CIQUAL et
/// Open Food Facts).
///
/// Clés composites `"ciqual:123"` / `"off:3017620422003"` (voir
/// `ResultatRechercheAliment.id`). Les aliments CIQUAL sont résolus à la volée
/// depuis la base locale ; les produits OFF n'ont pas de base locale, donc un
/// **snapshot JSON** du produit est conservé au moment de l'utilisation.
///
/// Persisté dans le hub SwiftData (`AlimentRecentEnregistre`), donc
/// synchronisé par CloudKit : les habitudes de saisie (dernière quantité,
/// taille de portion, mode) survivent à une réinstallation. Elles
/// représentent beaucoup d'usage accumulé — les perdre obligerait à re-régler
/// chaque aliment.
///
/// L'état est tenu en mémoire pour la lecture (`position` est appelé pendant
/// le classement des résultats de recherche) et le store n'est écrit qu'aux
/// mutations.
@Observable
final class AlimentsRecentsService {
    static let shared = AlimentsRecentsService()

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

    /// Glucides pour 100 g corrigés par l'utilisateur, quand l'étiquette de
    /// son paquet contredit la base. Même statut durable que
    /// `taillesPortion` : survit à la sortie de la liste MRU (voir
    /// `sauvegarder`), sinon la correction serait à ressaisir au prochain
    /// scan, paquet en main.
    private var glucidesCorriges: [String: Double] = [:]

    private var contexte: ModelContext?

    private init() {}

    /// Branche le service sur le hub et charge l'état. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    /// Recharge depuis le store — appelé après un import CloudKit.
    func recharger() {
        guard let contexte else { return }
        let lignes = (try? contexte.fetch(
            FetchDescriptor<AlimentRecentEnregistre>(sortBy: [SortDescriptor(\.rang)])
        )) ?? []

        // Seules les lignes marquées récentes reconstituent la liste MRU :
        // les autres ne sont là que pour leur donnée durable (voir
        // `AlimentRecentEnregistre.estRecent`).
        clesRecentes = lignes.filter(\.estRecent).map(\.cle)
        snapshotsOFF = [:]
        quantites = [:]
        taillesPortion = [:]
        modesQuantite = [:]
        glucidesCorriges = [:]

        for ligne in lignes {
            if let data = ligne.snapshot,
               let produit = try? JSONDecoder().decode(AlimentOFF.self, from: data) {
                snapshotsOFF[produit.code] = produit
            }
            if let quantite = ligne.quantite { quantites[ligne.cle] = quantite }
            if let taille = ligne.taillePortion { taillesPortion[ligne.cle] = taille }
            if let mode = ligne.modeQuantite.flatMap(ModeQuantiteAliment.init(rawValue:)) {
                modesQuantite[ligne.cle] = mode
            }
            if let glucides = ligne.glucidesPour100g { glucidesCorriges[ligne.cle] = glucides }
        }
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

    // MARK: - Correction des glucides

    /// Glucides pour 100 g corrigés pour cet aliment, `nil` si la valeur
    /// d'origine (CIQUAL ou Open Food Facts) n'a jamais été rectifiée.
    ///
    /// Lu par `ResultatRechercheAliment.glucides` — point d'injection unique,
    /// donc tout ce qui calcule une dose ou affiche des glucides suit.
    func glucidesCorriges(_ aliment: ResultatRechercheAliment) -> Double? {
        glucidesCorriges[aliment.id]
    }

    func glucidesCorriges(cle: String) -> Double? {
        glucidesCorriges[cle]
    }

    /// Enregistre la valeur lue sur l'étiquette. Persisté immédiatement,
    /// indépendamment de la validation du repas en cours : c'est une
    /// correction durable du référentiel pour cet utilisateur, pas un réglage
    /// de saisie.
    func corrigerGlucides(_ aliment: ResultatRechercheAliment, pour100g: Double) {
        guard pour100g >= 0 else { return }
        glucidesCorriges[aliment.id] = pour100g
        sauvegarder()
    }

    /// Restaure la valeur d'origine de la base.
    func restaurerGlucides(_ aliment: ResultatRechercheAliment) {
        restaurerGlucides(cle: aliment.id)
    }

    func restaurerGlucides(cle: String) {
        guard glucidesCorriges.removeValue(forKey: cle) != nil else { return }
        sauvegarder()
    }

    /// Aliments dont les glucides ont été corrigés, résolus depuis le
    /// référentiel courant et triés par nom affiché — alimente la page de
    /// gestion. Une clé irrésoluble (produit OFF dont le snapshot a été purgé
    /// avec la liste MRU) est ignorée à l'affichage mais **conserve sa
    /// correction** : elle se réappliquera au prochain scan du même
    /// code-barres.
    var alimentsCorriges: [ResultatRechercheAliment] {
        glucidesCorriges.keys
            .compactMap { resoudre(cle: $0) }
            .sorted { $0.nom.localizedCaseInsensitiveCompare($1.nom) == .orderedAscending }
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
        glucidesCorriges = [:]
        guard let contexte else { return }
        // Objet par objet : un `delete(model:)` ne serait pas exporté vers
        // CloudKit et les récents reviendraient à la synchronisation suivante.
        for ligne in lignesExistantes() {
            contexte.delete(ligne)
        }
        try? contexte.save()
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
        // Les produits corrigés gardent leur snapshot même hors MRU : sans
        // lui, `alimentsCorriges` ne saurait plus les résoudre et la page de
        // gestion afficherait une correction sans nom ni marque.
        let clesAvecSnapshot = Set(clesRecentes).union(glucidesCorriges.keys)
        let codesActifs = Set(clesAvecSnapshot.compactMap { cle -> String? in
            guard cle.hasPrefix("off:") else { return nil }
            return String(cle.dropFirst("off:".count))
        })
        snapshotsOFF = snapshotsOFF.filter { codesActifs.contains($0.key) }

        let clesActives = Set(clesRecentes)
        quantites = quantites.filter { clesActives.contains($0.key) }
    }

    // MARK: - Persistance

    private func lignesExistantes() -> [AlimentRecentEnregistre] {
        guard let contexte else { return [] }
        return (try? contexte.fetch(FetchDescriptor<AlimentRecentEnregistre>())) ?? []
    }

    /// Réécrit les lignes pour refléter l'état mémoire : met à jour celles
    /// qui subsistent (en conservant leur identité, donc sans churn côté
    /// CloudKit), crée les nouvelles, supprime celles sorties de la liste.
    private func sauvegarder() {
        guard let contexte else { return }

        var parCle: [String: AlimentRecentEnregistre] = [:]
        for ligne in lignesExistantes() {
            // Doublon éventuel (deux appareils ayant inséré la même clé
            // avant fusion) : on garde la première et on supprime le reste.
            if parCle[ligne.cle] == nil {
                parCle[ligne.cle] = ligne
            } else {
                contexte.delete(ligne)
            }
        }

        // Les clés à conserver : la liste MRU, plus celles portant une taille
        // de portion ou une correction de glucides. Ces deux-là sont des
        // décisions durables de l'utilisateur (« un bol = 250 g », « mon
        // paquet indique 52 g ») : elles doivent survivre à la sortie de
        // l'aliment de la liste des récents, sinon elles seraient à
        // ressaisir — la correction, paquet en main. Ces clés hors MRU sont
        // rangées après, sans quantité ni snapshot (état de saisie, lui,
        // périmé).
        let clesDurables = Set(taillesPortion.keys).union(glucidesCorriges.keys)
        let clesHorsMRU = clesDurables.filter { !clesRecentes.contains($0) }.sorted()
        let aPersister = clesRecentes + clesHorsMRU

        for (rang, cle) in aPersister.enumerated() {
            let dansMRU = rang < clesRecentes.count
            // Snapshot conservé hors MRU pour un produit corrigé (voir
            // `nettoyerSnapshots`), sinon la correction deviendrait anonyme.
            let gardeSnapshot = dansMRU || glucidesCorriges[cle] != nil
            let snapshot = gardeSnapshot ? snapshotOFFEncode(pour: cle) : nil
            if let ligne = parCle.removeValue(forKey: cle) {
                ligne.rang = rang
                ligne.estRecent = dansMRU
                ligne.quantite = dansMRU ? quantites[cle] : nil
                ligne.taillePortion = taillesPortion[cle]
                ligne.modeQuantite = modesQuantite[cle]?.rawValue
                ligne.snapshot = snapshot
                ligne.glucidesPour100g = glucidesCorriges[cle]
            } else {
                contexte.insert(AlimentRecentEnregistre(
                    cle: cle,
                    rang: rang,
                    estRecent: dansMRU,
                    quantite: dansMRU ? quantites[cle] : nil,
                    taillePortion: taillesPortion[cle],
                    modeQuantite: modesQuantite[cle]?.rawValue,
                    snapshot: snapshot,
                    glucidesPour100g: glucidesCorriges[cle]
                ))
            }
        }

        // Ce qui reste ne sert plus à rien : ni récent, ni porteur d'une
        // taille de portion ou d'une correction de glucides.
        for ligne in parCle.values {
            contexte.delete(ligne)
        }

        try? contexte.save()
    }

    private func snapshotOFFEncode(pour cle: String) -> Data? {
        guard cle.hasPrefix("off:") else { return nil }
        let code = String(cle.dropFirst("off:".count))
        guard let produit = snapshotsOFF[code] else { return nil }
        return try? JSONEncoder().encode(produit)
    }
}
