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
    /// Cause du verdict `.mauvais` — sert uniquement à colorer le point du
    /// graphique (hypo et pic élevé sont deux événements opposés). Le mining
    /// lui-même ne la lit pas : il ne distingue que « bon » vs « pas bon ».
    var raisonMauvais: RaisonMauvaisVerdict? = nil
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
        case .doseNettementFaible: return "dose nettement plus faible que votre ratio"
        case .doseProche:          return "votre ratio actuel"
        case .doseNettementForte:  return "dose nettement plus élevée que votre ratio"
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
    /// Repas exploitables dans ce groupe — **toujours peuplé**. Sert de
    /// dénominateur affiché : un taux sur petit effectif reste honnête tant
    /// que le nombre de repas est visible à côté.
    let effectif: Int
    /// Seulement les tranches à l'effectif suffisant
    /// (`effectifMinimalBucket`) — silence sur les autres.
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
/// Même famille que `CalculRepasARevoir` : énumération exhaustive,
/// dénominateurs bruts, seuils stricts. Pas de modèle entraîné — chaque
/// chiffre est recomptable à la main depuis les repas listés.
nonisolated enum CalculRatioObserve {

    /// Effectif minimal d'un bucket pour être affiché — **seul garde-fou de
    /// volume** du mining.
    ///
    /// Un second seuil par groupe (30 repas avant tout résultat) existait
    /// jusqu'au 2026-08-05 : supprimé car largement redondant avec celui-ci
    /// (c'est le bucket, pas le groupe, qui porte le risque de bruit) et
    /// contraire à la dégradation gracieuse de l'app — il masquait des
    /// dénominateurs déjà honnêtes (« 4 bons sur 6 ») pendant des semaines,
    /// et le compteur repartait à zéro sans le dire au moindre changement de
    /// ratio. Un taux sur petit effectif est désormais montré avec son
    /// dénominateur, à l'utilisateur de juger du recul.
    static let effectifMinimalBucket = 5
    /// Écart minimal de taux de bons verdicts entre bucket optimal et bucket
    /// configuré pour signaler un écart (points de taux).
    static let ecartMinimal = 0.25
    /// Tolérance (±) autour du **ratio configuré**, exprimée en grammes par
    /// unité — la même unité que les réglages (`1u/12g`).
    ///
    /// Remplace depuis le 2026-08-08 une tolérance relative de ±20 % sur la
    /// dose. Le pourcentage ne parlait pas : il ne correspondait à rien de
    /// manipulable, et sa largeur en grammes variait avec le ratio (±20 %
    /// autour de `1u/12g` couvrait `1u/10g` à `1u/15g`, soit cinq crans de
    /// réglage). En g/u, la bande se lit directement : `1u/11g` à `1u/13g`.
    static let toleranceGrammesParUnite = 1.0

    // MARK: Point d'entrée

    static func analyser(entrees: [EntreeRatioRepas]) -> AnalyseRatioObserve {
        let groupes = Dictionary(grouping: entrees, by: \.groupe)
        let sections = groupes.map { groupe, repas in
            construireSection(groupe: groupe, repas: repas)
        }.sorted { ordreJournee($0.groupe) < ordreJournee($1.groupe) }

        return AnalyseRatioObserve(sections: sections)
    }

    /// Libellé d'un groupe — moment de la journée, ou « Tous les repas » en
    /// mode ratio unique (`groupe == nil`).
    static func libelleGroupe(_ groupe: SectionRepas?) -> String {
        groupe?.titre ?? "Tous les repas"
    }

    /// Rang chronologique d'un groupe, pour présenter les moments dans
    /// l'ordre où ils arrivent dans la journée.
    ///
    /// Le tri se faisait auparavant sur le libellé, donc par ordre
    /// alphabétique : « Déjeuner » passait avant « Petit déjeuner ». La
    /// déclaration de `SectionRepas` est déjà chronologique, il suffit de la
    /// suivre. Le mode ratio unique (`nil`) n'a qu'un seul groupe, son rang
    /// n'a pas d'incidence.
    private static func ordreJournee(_ groupe: SectionRepas?) -> Int {
        guard let groupe else { return -1 }
        return SectionRepas.allCases.firstIndex(of: groupe) ?? .max
    }

    // MARK: Classification en tranche

    /// Classe un repas en comparant son **ratio effectif** (`glucides ÷ dose
    /// réellement donnée`, en g/u) au ratio configuré, lui aussi reconstitué
    /// en g/u (`glucides ÷ dose suggérée`).
    ///
    /// Attention au sens : le ratio s'exprimant en grammes couverts par unité,
    /// il varie **à l'inverse** de l'insuline. Un ratio effectif *plus élevé*
    /// que le configuré (plus de grammes par unité) signifie qu'on a mis
    /// *moins* d'insuline — donc `.doseNettementFaible`.
    static func tranche(glucides: Int, doseAppliquee: Double, doseSuggeree: Double) -> TrancheRatio {
        guard doseSuggeree > 0, doseAppliquee > 0, glucides > 0 else { return .doseProche }
        let ratioEffectif = Double(glucides) / doseAppliquee
        let ratioConfigure = Double(glucides) / doseSuggeree
        let ecart = ratioEffectif - ratioConfigure
        if ecart >= toleranceGrammesParUnite { return .doseNettementFaible }
        if ecart <= -toleranceGrammesParUnite { return .doseNettementForte }
        return .doseProche
    }

    // MARK: Groupe (moment de repas)

    private static func construireSection(
        groupe: SectionRepas?, repas: [EntreeRatioRepas]
    ) -> ObservationRatioSection {
        let parTranche = Dictionary(grouping: repas) {
            tranche(glucides: $0.glucides, doseAppliquee: $0.doseAppliquee, doseSuggeree: $0.doseSuggeree)
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
