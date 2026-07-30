//
//  CalculRatioObserve.swift
//  diaviz
//

import Foundation

// MARK: - Groupe de mining

/// Clé de regroupement du mining — soit un moment de repas (ratio de base,
/// matin/midi/soir/…), soit une raison d'ajustement intentionnel (sport
/// récent, glycémie basse avant repas…). Un repas ajusté n'alimente **jamais**
/// un groupe `.moment` — il est classé uniquement dans le(s) groupe(s)
/// `.ajustement` correspondant(s), pour ne pas polluer le signal du ratio de
/// base avec des doses déjà compensées manuellement. Même mécanique de calcul
/// pour les deux cas — seule la clé de regroupement change.
nonisolated enum GroupeRatio: Hashable, Sendable {
    case moment(SectionRepas?)
    case ajustement(RaisonAjustement)

    var libelle: String {
        switch self {
        case .moment(let section): return section?.titre ?? "Tous les repas"
        case .ajustement(let raison): return raison.libelle
        }
    }

    /// Ordre d'affichage stable : moments d'abord (triés par titre), puis
    /// ajustements (triés par libellé).
    fileprivate var cleTri: (Int, String) {
        switch self {
        case .moment: return (0, libelle)
        case .ajustement: return (1, libelle)
        }
    }
}

// MARK: - Entrée

/// Un repas exploitable pour le mining du ratio observé — mappé par
/// `AnalyseRatioService` depuis `Repas.verdictPersiste`/`ratioEffectifPersiste`
/// (tout l'historique, pas seulement la fenêtre CGM récente gardée en
/// mémoire). Value type découplé de SwiftData, même pattern qu'`EntreesBasale`.
///
/// Un repas avec plusieurs ajustements produit **une entrée par raison**
/// (même repas dupliqué dans plusieurs `EntreeRatioRepas`, une par groupe) —
/// c'est `AnalyseRatioService` qui gère cette explosion ; `totalRepasAnalyses`
/// (transmis séparément à `analyser`) compte les repas **distincts**, pas les
/// entrées, pour ne pas gonfler artificiellement le seuil global.
nonisolated struct EntreeRatioRepas: Sendable {
    let groupe: GroupeRatio
    /// Dose couvrant les glucides (`totalInsuline - doseCorrection`).
    let doseAppliquee: Double
    /// Dose suggérée par le ratio **configuré actuellement** dans le profil
    /// pour la section réelle du repas — pas d'historique de changement de
    /// ratio tracé (contrairement à la dose de lente pour B1), donc les repas
    /// anciens sont comparés au ratio d'aujourd'hui. Limite connue, documentée.
    let doseSuggeree: Double
    let glucides: Int
    let verdict: VerdictGlycemique
}

// MARK: - Tranche de ratio

/// Tranche d'écart entre la dose appliquée et la dose suggérée par le ratio
/// configuré — miroir de `TrancheCoucher` (B2/B3), axe « levier » principal.
nonisolated enum TrancheRatio: String, Sendable, CaseIterable {
    case doseNettementFaible
    case doseProche
    case doseNettementForte

    var libelle: String {
        switch self {
        case .doseNettementFaible: return "dose nettement plus faible que ton ratio"
        case .doseProche:          return "ton ratio actuel"
        case .doseNettementForte:  return "dose nettement plus élevée que ton ratio"
        }
    }
}

// MARK: - Résultat par bucket

nonisolated struct BucketRatioObserve: Sendable, Equatable {
    let tranche: TrancheRatio
    let total: Int
    let bons: Int

    var tauxBon: Double { Double(bons) / Double(max(1, total)) }
}

/// Écart significatif détecté entre le bucket « proche du ratio configuré »
/// et un autre bucket au taux de bons verdicts nettement supérieur. Co-
/// occurrence observée avec dénominateurs — jamais une dose à utiliser.
nonisolated struct EcartRatioObserve: Sendable, Equatable {
    let bonsConfigure: Int
    let effectifConfigure: Int
    let trancheOptimale: TrancheRatio
    let bonsOptimal: Int
    let effectifOptimal: Int

    var tauxConfigure: Double { Double(bonsConfigure) / Double(max(1, effectifConfigure)) }
    var tauxOptimal: Double { Double(bonsOptimal) / Double(max(1, effectifOptimal)) }
}

nonisolated struct ObservationRatioSection: Sendable, Equatable {
    let groupe: GroupeRatio
    /// Seulement les tranches à l'effectif suffisant (silence sinon).
    let buckets: [BucketRatioObserve]
    let ecart: EcartRatioObserve?
}

nonisolated struct AnalyseRatioObserve: Sendable, Equatable {
    /// Repas **distincts** exploitables (verdict connu, hors contexte libre)
    /// — pas le nombre d'entrées, qui peut dupliquer un repas ajusté sur
    /// plusieurs raisons.
    let totalRepasAnalyses: Int
    let sections: [ObservationRatioSection]

    static var vide: AnalyseRatioObserve { .init(totalRepasAnalyses: 0, sections: []) }
}

// MARK: - Calculateur

/// Mining du ratio observé (cœur ML de R1) : bucketise chaque repas exploité
/// par l'écart entre dose appliquée et dose suggérée par le ratio configuré,
/// lit le taux de bons verdicts par bucket, détecte un écart significatif.
///
/// Même famille que `CalculSituationsCoucher` : énumération exhaustive,
/// dénominateurs bruts, seuils stricts. Pas de modèle entraîné — chaque
/// chiffre est recomptable à la main depuis les repas listés.
nonisolated enum CalculRatioObserve {

    /// Repas analysés (tout l'historique) requis avant d'afficher quoi que
    /// ce soit — cadrage R1 (doc architecture).
    static let donneesMinimales = 30
    /// Effectif minimal d'un bucket pour être affiché.
    static let effectifMinimalBucket = 5
    /// Écart minimal de taux de bons verdicts entre bucket optimal et bucket
    /// configuré pour signaler un écart (points de taux).
    static let ecartMinimal = 0.25
    /// Tolérance (±) autour de la dose suggérée pour le bucket « proche ».
    static let toleranceRatio = 0.20

    // MARK: Point d'entrée

    static func analyser(entrees: [EntreeRatioRepas], totalRepasAnalyses: Int) -> AnalyseRatioObserve {
        guard totalRepasAnalyses >= donneesMinimales else {
            return AnalyseRatioObserve(totalRepasAnalyses: totalRepasAnalyses, sections: [])
        }

        let groupes = Dictionary(grouping: entrees, by: \.groupe)
        let sections = groupes.map { groupe, repas in
            construireSection(groupe: groupe, repas: repas)
        }.sorted { $0.groupe.cleTri < $1.groupe.cleTri }

        return AnalyseRatioObserve(totalRepasAnalyses: totalRepasAnalyses, sections: sections)
    }

    // MARK: Classification en tranche

    static func tranche(doseAppliquee: Double, doseSuggeree: Double) -> TrancheRatio {
        guard doseSuggeree > 0 else { return .doseProche }
        let ratio = doseAppliquee / doseSuggeree
        if ratio <= 1 - toleranceRatio { return .doseNettementFaible }
        if ratio >= 1 + toleranceRatio { return .doseNettementForte }
        return .doseProche
    }

    // MARK: Groupe (moment de repas ou raison d'ajustement)

    private static func construireSection(
        groupe: GroupeRatio, repas: [EntreeRatioRepas]
    ) -> ObservationRatioSection {
        let parTranche = Dictionary(grouping: repas) {
            tranche(doseAppliquee: $0.doseAppliquee, doseSuggeree: $0.doseSuggeree)
        }

        let buckets = TrancheRatio.allCases.compactMap { t -> BucketRatioObserve? in
            guard let repasTranche = parTranche[t], repasTranche.count >= effectifMinimalBucket else { return nil }
            let bons = repasTranche.filter { $0.verdict == .bon }.count
            return BucketRatioObserve(tranche: t, total: repasTranche.count, bons: bons)
        }

        return ObservationRatioSection(
            groupe: groupe, buckets: buckets, ecart: detecterEcart(buckets)
        )
    }

    // MARK: Détection d'écart

    private static func detecterEcart(_ buckets: [BucketRatioObserve]) -> EcartRatioObserve? {
        guard let configure = buckets.first(where: { $0.tranche == .doseProche }) else { return nil }
        let meilleur = buckets
            .filter { $0.tranche != .doseProche }
            .max { $0.tauxBon < $1.tauxBon }
        guard let meilleur, meilleur.tauxBon - configure.tauxBon >= ecartMinimal else { return nil }
        return EcartRatioObserve(
            bonsConfigure: configure.bons, effectifConfigure: configure.total,
            trancheOptimale: meilleur.tranche, bonsOptimal: meilleur.bons, effectifOptimal: meilleur.total
        )
    }
}
