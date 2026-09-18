//
//  CalculBilanCorrections.swift
//  diaviz
//

import Foundation

// MARK: - Entrées (value types, découplés de SwiftData)

/// Faits bruts nécessaires au bilan des corrections — mêmes fetchs partagés
/// que B3 (`ChargeurFaitsCoucher`), mais sans ancrage de nuit : toute heure
/// de la journée est retenue.
nonisolated struct EntreesBilanCorrections: Sendable {
    let lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)]
    let rapides: [(heure: Date, dose: Double, correction: Bool)]
    let resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)]
    let pauses: [(debut: Date, fin: Date?)]
    /// Repas hors resucrage — sert uniquement à détecter la concomitance
    /// d'un repas (`CorrectionEvaluee.auRepas`), pas à mesurer des glucides.
    let repas: [(heure: Date, glucides: Int)]
}

nonisolated struct ConfigBilanCorrections: Sendable {
    /// Cible haute (mg/dL) — au-delà, une correction jugée « insuffisante »
    /// si la glycémie n'y redescend pas. Profil (`seuilsGlycemiques.hyperglycemie`).
    var cibleHaute: Int = 180
    /// Seuil hypo (mg/dL) — sous ce seuil dans les 6h : « sur-correction ».
    var seuilHypo: Int = 70
    var diaHeures: Double = 4
    var picMinutes: Double = 75
    /// Ratio de correction (ISF) du profil, en mg/dL baissés par unité —
    /// `nil` si non renseigné (champ optionnel du profil).
    var ratioCorrection: Double?
    /// Fenêtre (min, symétrique) de concomitance avec un repas — profil
    /// (`preferencesAvancees.fenetreRepasCorrectionMinutes`).
    var fenetreRepasMinutes: Double = CalculBilanCorrections.fenetreRepasMinutesParDefaut
}

/// Assembleur **bilan des corrections** : dérivation pure, jamais persistée.
/// Reprend la classification de B3 (`IssueCorrection`) mais sans restriction
/// horaire — chaque rapide `motif == .correction` de la fenêtre chargée est
/// évaluée, coucher ou pas.
///
/// Scinde le résultat en deux portées non comparables (`isolees` / `auRepas`)
/// : une correction prise près d'un repas voit sa courbe CGM portée par les
/// glucides autant que par l'insuline, la mélanger aux corrections isolées
/// fausserait le taux d'adaptation et la segmentation dose vs ratio.
///
/// Doc : Eraser « Diaviz / Corrections — Bilan toutes heures ».
nonisolated enum CalculBilanCorrections {

    private static let fenetreSurCorrection: TimeInterval = 6 * 3600
    private static let fenetreInsuffisance: TimeInterval = 2 * 3600

    /// Effectif minimal d'une tranche de dose pour être affichée — même
    /// garde-fou que `CalculRatioObserve` (R1) : c'est la tranche, pas le
    /// total, qui porte le risque de bruit.
    static let effectifMinimalBucket = 5

    /// Tolérance (±, en unités) autour de la dose suggérée par le ratio de
    /// correction pour être classée « proche ».
    static let toleranceUnites = 0.5

    /// Fenêtre par défaut (min) de concomitance avec un repas, réglable
    /// dans Profil → Ratios (`SectionCorrectionsReglages`).
    static let fenetreRepasMinutesParDefaut = 30.0

    // MARK: - Point d'entrée

    static func analyser(
        entrees: EntreesBilanCorrections,
        config: ConfigBilanCorrections = ConfigBilanCorrections()
    ) -> BilanCorrections {
        let correctionsHorsPause = entrees.rapides.filter {
            $0.correction && !enPause($0.heure, pauses: entrees.pauses)
        }

        let corrections: [CorrectionEvaluee] = correctionsHorsPause.compactMap { correction in
            construireCorrection(correction, entrees: entrees, config: config)
        }
        .sorted { $0.date > $1.date }

        let (auRepas, isolees) = corrections.partitioned(by: \.auRepas)

        return BilanCorrections(
            isolees: SousBilanCorrections(corrections: isolees, buckets: construireBuckets(isolees)),
            auRepas: SousBilanCorrections(corrections: auRepas, buckets: construireBuckets(auRepas))
        )
    }

    private static func enPause(_ instant: Date, pauses: [(debut: Date, fin: Date?)]) -> Bool {
        pauses.contains { p in
            let fin = p.fin ?? .distantFuture
            return instant >= p.debut && instant <= fin
        }
    }

    // MARK: - Une correction

    private static func construireCorrection(
        _ correction: (heure: Date, dose: Double, correction: Bool),
        entrees: EntreesBilanCorrections,
        config: ConfigBilanCorrections
    ) -> CorrectionEvaluee? {
        let heure = correction.heure
        guard let (issue, picMax) = issueEtPic(entrees.lectures, apres: heure, config: config) else {
            return nil   // pas encore assez de recul CGM pour classer
        }

        let glycemie = valeurProche(entrees.lectures, a: heure) ?? 0
        let injectionsAvant = entrees.rapides
            .filter { $0.heure < heure }
            .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) }
        let iobAvant = iob(injectionsAvant, a: heure, config: config)

        let hypoCausee = issue == .surCorrection
        let iobAuMomentHypo = hypoCausee
            ? iobAuMomentDuPassageHypo(correction, entrees: entrees, config: config)
            : nil

        let rechute = DetectionRechute.rechute(
            lectures: entrees.lectures,
            resucrages: entrees.resucrages,
            de: heure,
            seuilHypo: config.seuilHypo
        )

        return CorrectionEvaluee(
            id: UUID(), date: heure, glycemie: glycemie, dose: correction.dose,
            iobAvant: iobAvant, picMax: picMax, issue: issue,
            iobAuMomentHypo: iobAuMomentHypo, rechute: rechute,
            tranche: tranche(glycemie: glycemie, dose: correction.dose, config: config),
            auRepas: repasConcomitant(entrees.repas, de: heure, fenetreMinutes: config.fenetreRepasMinutes)
        )
    }

    // MARK: - Classification (issue + pic max)

    /// `nil` si pas assez de CGM après la correction pour trancher (correction
    /// trop récente) — cette correction n'est alors pas encore affichable.
    private static func issueEtPic(
        _ lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)],
        apres heure: Date,
        config: ConfigBilanCorrections
    ) -> (issue: IssueCorrection, picMax: Int)? {
        let fenetre6h = lectures.filter {
            $0.date > heure && $0.date <= heure.addingTimeInterval(fenetreSurCorrection)
        }
        guard !fenetre6h.isEmpty else { return nil }

        let picMax = fenetre6h.map(\.valeur).max() ?? 0

        if fenetre6h.contains(where: { $0.valeur < config.seuilHypo }) {
            return (.surCorrection, picMax)
        }

        let fenetre2h = fenetre6h.filter { $0.date <= heure.addingTimeInterval(fenetreInsuffisance) }
        guard !fenetre2h.isEmpty else { return nil }

        let resteHaut = fenetre2h.allSatisfy { $0.valeur > config.cibleHaute }
        return (resteHaut ? .insuffisant : .adapte, picMax)
    }

    // MARK: - IOB

    private static func iob(
        _ injections: [InjectionPourIOB], a instant: Date, config: ConfigBilanCorrections
    ) -> Double? {
        let valeur = IOBCalculateur.iob(
            a: instant, injections: injections, diaHeures: config.diaHeures, picMinutes: config.picMinutes
        )
        return valeur > 0.05 ? valeur : nil
    }

    /// IOB (dose de la correction incluse) à l'instant précis du passage sous
    /// le seuil hypo — `nil` si aucune lecture sous le seuil n'est trouvée
    /// dans la fenêtre (garde-fou théorique : `hypoCausee` l'implique déjà).
    private static func iobAuMomentDuPassageHypo(
        _ correction: (heure: Date, dose: Double, correction: Bool),
        entrees: EntreesBilanCorrections,
        config: ConfigBilanCorrections
    ) -> Double? {
        let fenetre = entrees.lectures.filter {
            $0.date > correction.heure && $0.date <= correction.heure.addingTimeInterval(fenetreSurCorrection)
        }
        guard let instantHypo = fenetre.first(where: { $0.valeur < config.seuilHypo })?.date else { return nil }

        let injections = entrees.rapides
            .filter { $0.heure <= instantHypo }
            .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) }
        return iob(injections, a: instantHypo, config: config)
    }

    // MARK: - Contexte

    private static func valeurProche(
        _ lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)], a instant: Date
    ) -> Int? {
        lectures.min(by: { abs($0.date.timeIntervalSince(instant)) < abs($1.date.timeIntervalSince(instant)) })?.valeur
    }

    /// `true` si un repas tombe dans la fenêtre symétrique autour de
    /// `instant` — la fenêtre est symétrique (avant **et** après) parce que
    /// les glucides d'un repas pris juste après la correction pèsent tout
    /// autant sur la courbe qui suit que ceux d'un repas pris juste avant.
    private static func repasConcomitant(
        _ repas: [(heure: Date, glucides: Int)], de instant: Date, fenetreMinutes: Double
    ) -> Bool {
        let demiFenetre = fenetreMinutes * 60
        return repas.contains { abs($0.heure.timeIntervalSince(instant)) <= demiFenetre }
    }

    // MARK: - Segmentation dose vs ratio de correction

    /// `nil` si le ratio de correction n'est pas configuré, ou si la
    /// glycémie n'était pas hyper (le ratio ne suggère alors aucune dose de
    /// référence) — dégradation gracieuse, pas d'écart inventé.
    private static func tranche(
        glycemie: Int, dose: Double, config: ConfigBilanCorrections
    ) -> TrancheDoseCorrection? {
        guard let ratio = config.ratioCorrection, ratio > 0,
              glycemie > config.cibleHaute, dose > 0 else { return nil }
        let doseSuggeree = Double(glycemie - config.cibleHaute) / ratio
        let ecart = dose - doseSuggeree
        if ecart >= toleranceUnites { return .doseNettementForte }
        if ecart <= -toleranceUnites { return .doseNettementFaible }
        return .doseProche
    }

    private static func construireBuckets(_ corrections: [CorrectionEvaluee]) -> [BucketDoseCorrection] {
        let classables = corrections.filter { $0.tranche != nil }
        let parTranche = Dictionary(grouping: classables) { $0.tranche! }

        return TrancheDoseCorrection.allCases.compactMap { t -> BucketDoseCorrection? in
            guard let groupe = parTranche[t], groupe.count >= effectifMinimalBucket else { return nil }
            let adaptees = groupe.count(where: { $0.issue == .adapte })
            return BucketDoseCorrection(tranche: t, total: groupe.count, adaptees: adaptees)
        }
    }
}

// MARK: - Partition

private extension Array {
    /// Découpe en (éléments qui satisfont le prédicat, les autres) — évite
    /// deux `.filter` séquentiels sur la même collection.
    func partitioned(by predicat: (Element) -> Bool) -> (matches: [Element], reste: [Element]) {
        var matches: [Element] = []
        var reste: [Element] = []
        for element in self {
            if predicat(element) { matches.append(element) } else { reste.append(element) }
        }
        return (matches, reste)
    }
}
