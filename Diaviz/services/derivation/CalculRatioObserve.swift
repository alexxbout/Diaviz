//
//  CalculRatioObserve.swift
//  diaviz
//

import Foundation

// MARK: - Entrée

/// Un repas exploitable pour le mining du ratio observé — mappé par
/// `AnalyseRatioService` depuis `Repas.verdictPersiste`/`ratioEffectifPersiste`
/// (tout l'historique, pas seulement la fenêtre CGM récente gardée en
/// mémoire). Value type découplé de SwiftData, même pattern qu'`EntreesBasale`.
///
/// `groupe` est le moment du repas (`nil` en mode ratio unique) — les repas
/// ajustés (`Repas.ajustements` non vide) sont exclus en amont par
/// `AnalyseRatioService`, jamais représentés ici.
nonisolated struct EntreeRatioRepas: Sendable, Equatable {
    /// Identité du repas source (`Repas.id`) — sert de graine stable pour
    /// le jitter du graphique de dispersion (`GraphiqueZonesRatio`), pas
    /// de recalcul aléatoire à chaque rendu.
    let id: UUID
    let groupe: SectionRepas?
    /// Dose couvrant les glucides (`totalInsuline - doseCorrection`).
    let doseAppliquee: Double
    /// Dose suggérée par le ratio **configuré actuellement** dans le profil
    /// pour la section réelle du repas — pas d'historique de changement de
    /// ratio tracé au niveau du calcul lui-même (le filtrage par date de
    /// changement se fait en amont, dans `AnalyseRatioService`).
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
    let groupe: SectionRepas?
    /// Repas exploitables dans ce groupe — **toujours peuplé**, indépendant
    /// du seuil `donneesMinimales`. Alimente la progression affichée avant
    /// que le groupe ait assez de données pour un vrai résultat.
    let effectif: Int
    /// Seulement les tranches à l'effectif suffisant (silence sinon). Vide
    /// tant que `effectif < donneesMinimales`.
    let buckets: [BucketRatioObserve]
    let ecart: EcartRatioObserve?
    /// Tous les repas du groupe, **toujours peuplé** — alimente le
    /// graphique de dispersion (`GraphiqueZonesRatio`) qui a besoin des
    /// points individuels, pas seulement des agrégats de `buckets`.
    let entrees: [EntreeRatioRepas]
}

nonisolated struct AnalyseRatioObserve: Sendable, Equatable {
    let sections: [ObservationRatioSection]

    static var vide: AnalyseRatioObserve { .init(sections: []) }
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

    /// Repas analysés requis **par groupe** (moment) avant d'afficher un
    /// résultat pour ce groupe — pas un seuil global : changer le ratio d'un
    /// moment ne doit jamais faire disparaître l'analyse des autres.
    static let donneesMinimales = 30
    /// Effectif minimal d'un bucket pour être affiché.
    static let effectifMinimalBucket = 5
    /// Écart minimal de taux de bons verdicts entre bucket optimal et bucket
    /// configuré pour signaler un écart (points de taux).
    static let ecartMinimal = 0.25
    /// Tolérance (±) autour de la dose suggérée pour le bucket « proche ».
    static let toleranceRatio = 0.20

    // MARK: Point d'entrée

    static func analyser(entrees: [EntreeRatioRepas]) -> AnalyseRatioObserve {
        let groupes = Dictionary(grouping: entrees, by: \.groupe)
        let sections = groupes.map { groupe, repas in
            construireSection(groupe: groupe, repas: repas)
        }.sorted { libelleGroupe($0.groupe) < libelleGroupe($1.groupe) }

        return AnalyseRatioObserve(sections: sections)
    }

    /// Libellé d'un groupe — moment de la journée, ou « Tous les repas » en
    /// mode ratio unique (`groupe == nil`).
    static func libelleGroupe(_ groupe: SectionRepas?) -> String {
        groupe?.titre ?? "Tous les repas"
    }

    // MARK: Classification en tranche

    static func tranche(doseAppliquee: Double, doseSuggeree: Double) -> TrancheRatio {
        guard doseSuggeree > 0 else { return .doseProche }
        let ratio = doseAppliquee / doseSuggeree
        if ratio <= 1 - toleranceRatio { return .doseNettementFaible }
        if ratio >= 1 + toleranceRatio { return .doseNettementForte }
        return .doseProche
    }

    // MARK: Groupe (moment de repas)

    private static func construireSection(
        groupe: SectionRepas?, repas: [EntreeRatioRepas]
    ) -> ObservationRatioSection {
        guard repas.count >= donneesMinimales else {
            return ObservationRatioSection(groupe: groupe, effectif: repas.count, buckets: [], ecart: nil, entrees: repas)
        }

        let parTranche = Dictionary(grouping: repas) {
            tranche(doseAppliquee: $0.doseAppliquee, doseSuggeree: $0.doseSuggeree)
        }

        let buckets = TrancheRatio.allCases.compactMap { t -> BucketRatioObserve? in
            guard let repasTranche = parTranche[t], repasTranche.count >= effectifMinimalBucket else { return nil }
            let bons = repasTranche.filter { $0.verdict == .bon }.count
            return BucketRatioObserve(tranche: t, total: repasTranche.count, bons: bons)
        }

        return ObservationRatioSection(
            groupe: groupe, effectif: repas.count, buckets: buckets, ecart: detecterEcart(buckets), entrees: repas
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
