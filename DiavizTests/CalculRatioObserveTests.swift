//
//  CalculRatioObserveTests.swift
//  DiavizTests
//
//  R1 — mining du ratio observé. Seuls garde-fous : 5 repas par tranche,
//  ±1 g/u autour du ratio configuré, 25 points de taux d'écart. Un `<` de
//  travers ici fait apparaître (ou disparaître) une alerte « écart détecté »
//  sur l'accueil.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculRatioObserveTests {

    // MARK: - Fabriques

    /// `nombre` repas dans une tranche donnée, dont `bons` avec un bon verdict.
    /// La tranche est obtenue en jouant sur la dose appliquée, la dose
    /// suggérée restant à 10 u.
    private func repas(
        tranche: TrancheRatio,
        nombre: Int,
        bons: Int,
        groupe: SectionRepas? = .dejeuner
    ) -> [EntreeRatioRepas] {
        let doseAppliquee: Double = switch tranche {
        case .doseNettementFaible: 7
        case .doseProche:          10
        case .doseNettementForte:  13
        }
        return (0..<nombre).map { index in
            EntreeRatioRepas(
                id: UUID(),
                groupe: groupe,
                doseAppliquee: doseAppliquee,
                doseSuggeree: 10,
                glucides: 60,
                verdict: index < bons ? .bon : .mauvais
            )
        }
    }

    private func section(
        _ analyse: AnalyseRatioObserve, groupe: SectionRepas?
    ) -> ObservationRatioSection? {
        analyse.sections.first { $0.groupe == groupe }
    }

    // MARK: - Classification en tranche

    // Jeu d'essai calibré pour donner des ratios ronds : 99 g pour une dose
    // suggérée de 9,9 u = un ratio configuré de **1u/10g**. Les bornes de la
    // tolérance (±1 g/u) tombent alors sur des doses entières : 9 u donne
    // 1u/11g, 11 u donne 1u/9g.
    private static let glucidesTest = 99
    private static let doseSuggereeTest = 9.9

    private func tranche(dose: Double, doseSuggeree: Double = doseSuggereeTest) -> TrancheRatio {
        CalculRatioObserve.tranche(
            glucides: Self.glucidesTest, doseAppliquee: dose, doseSuggeree: doseSuggeree
        )
    }

    @Test("Dose égale à la dose suggérée → tranche « proche »")
    func trancheProche() {
        // 99 g pour 9,9 u = 1u/10g, exactement le ratio configuré.
        #expect(tranche(dose: 9.9) == .doseProche)
    }

    @Test("Bornes exactes de la tolérance de ±1 g/u")
    func bornesDeLaTolerance() {
        // Le ratio s'exprimant en grammes par unité, il varie à l'inverse de
        // l'insuline : moins de dose = plus de grammes couverts par unité.
        // 9 u → 1u/11g, soit +1 g/u : bascule en « dose plus faible ».
        #expect(tranche(dose: 9) == .doseNettementFaible)
        // 11 u → 1u/9g, soit −1 g/u : bascule en « dose plus élevée ».
        #expect(tranche(dose: 11) == .doseNettementForte)
        // Juste à l'intérieur de la bande, des deux côtés.
        #expect(tranche(dose: 9.1) == .doseProche)
        #expect(tranche(dose: 10.9) == .doseProche)
    }

    @Test("Dose suggérée nulle → classée « proche » (aucun écart calculable)")
    func doseSuggereeNulle() {
        #expect(tranche(dose: 5, doseSuggeree: 0) == .doseProche)
    }

    @Test("Dose appliquée nulle → classée « proche » (ratio effectif indéfini)")
    func doseAppliqueeNulle() {
        #expect(tranche(dose: 0) == .doseProche)
    }

    // MARK: - Effectifs et buckets

    @Test("Aucune entrée → analyse vide")
    func aucuneEntree() {
        #expect(CalculRatioObserve.analyser(entrees: []).sections.isEmpty)
    }

    @Test("Tranche à exactement 5 repas → bucket produit")
    func bucketAuSeuilExact() {
        let analyse = CalculRatioObserve.analyser(
            entrees: repas(tranche: .doseProche, nombre: 5, bons: 3)
        )
        let buckets = section(analyse, groupe: .dejeuner)?.buckets
        #expect(buckets?.count == 1)
        #expect(buckets?.first?.total == 5)
        #expect(buckets?.first?.bons == 3)
    }

    @Test("Tranche à 4 repas → silence sur le bucket, mais effectif conservé")
    func bucketSousLeSeuil() {
        let analyse = CalculRatioObserve.analyser(
            entrees: repas(tranche: .doseProche, nombre: 4, bons: 3)
        )
        let observation = section(analyse, groupe: .dejeuner)
        #expect(observation?.buckets.isEmpty == true)
        #expect(observation?.effectif == 4)
        #expect(observation?.entrees.count == 4)
        #expect(observation?.ecart == nil)
    }

    @Test("Les repas sont toujours exposés, même sous les seuils")
    func entreesToujoursPeuplees() {
        let entrees = repas(tranche: .doseNettementForte, nombre: 1, bons: 0)
        let observation = section(CalculRatioObserve.analyser(entrees: entrees), groupe: .dejeuner)
        #expect(observation?.effectif == 1)
        #expect(observation?.entrees.count == 1)
    }

    @Test("Taux de bons verdicts par bucket")
    func tauxParBucket() {
        let analyse = CalculRatioObserve.analyser(
            entrees: repas(tranche: .doseProche, nombre: 10, bons: 4)
        )
        #expect(section(analyse, groupe: .dejeuner)?.buckets.first?.tauxBon == 0.4)
    }

    // MARK: - Détection d'écart

    @Test("Écart exactement à 25 points → signalé")
    func ecartAuSeuilExact() {
        // Configuré 4/20 = 0,20 · optimal 9/20 = 0,45 → 25 points pile.
        let entrees = repas(tranche: .doseProche, nombre: 20, bons: 4)          // 0,20
            + repas(tranche: .doseNettementFaible, nombre: 20, bons: 9)         // 0,45
        let ecart = section(CalculRatioObserve.analyser(entrees: entrees), groupe: .dejeuner)?.ecart

        #expect(ecart != nil)
        #expect(ecart?.trancheOptimale == .doseNettementFaible)
        #expect(ecart?.bonsConfigure == 4)
        #expect(ecart?.effectifConfigure == 20)
        #expect(ecart?.bonsOptimal == 9)
        #expect(ecart?.effectifOptimal == 20)
    }

    @Test("Écart juste sous 25 points → non signalé")
    func ecartJusteSousLeSeuil() {
        // 0,20 vs 0,44 = 24 points.
        let entrees = repas(tranche: .doseProche, nombre: 25, bons: 5)
            + repas(tranche: .doseNettementFaible, nombre: 25, bons: 11)
        #expect(section(CalculRatioObserve.analyser(entrees: entrees), groupe: .dejeuner)?.ecart == nil)
    }

    @Test("Aucun bucket « proche » → aucun écart à mesurer")
    func aucunBucketConfigure() {
        let entrees = repas(tranche: .doseNettementFaible, nombre: 10, bons: 9)
        #expect(section(CalculRatioObserve.analyser(entrees: entrees), groupe: .dejeuner)?.ecart == nil)
    }

    @Test("Bucket latéral moins bon que le configuré → aucun écart")
    func bucketLateralMoinsBon() {
        let entrees = repas(tranche: .doseProche, nombre: 10, bons: 9)
            + repas(tranche: .doseNettementForte, nombre: 10, bons: 2)
        #expect(section(CalculRatioObserve.analyser(entrees: entrees), groupe: .dejeuner)?.ecart == nil)
    }

    @Test("Le meilleur des deux buckets latéraux est retenu")
    func meilleurBucketLateral() {
        let entrees = repas(tranche: .doseProche, nombre: 10, bons: 1)          // 0,10
            + repas(tranche: .doseNettementFaible, nombre: 10, bons: 5)         // 0,50
            + repas(tranche: .doseNettementForte, nombre: 10, bons: 9)          // 0,90
        let ecart = section(CalculRatioObserve.analyser(entrees: entrees), groupe: .dejeuner)?.ecart
        #expect(ecart?.trancheOptimale == .doseNettementForte)
    }

    @Test("Un bucket latéral sous l'effectif minimal ne peut pas porter d'écart")
    func bucketLateralSousEffectif() {
        let entrees = repas(tranche: .doseProche, nombre: 10, bons: 1)
            + repas(tranche: .doseNettementFaible, nombre: 4, bons: 4)
        #expect(section(CalculRatioObserve.analyser(entrees: entrees), groupe: .dejeuner)?.ecart == nil)
    }

    // MARK: - Groupes

    @Test("Un groupe par moment de la journée, indépendants")
    func groupesIndependants() {
        let entrees = repas(tranche: .doseProche, nombre: 6, bons: 6, groupe: .petitDejeuner)
            + repas(tranche: .doseProche, nombre: 5, bons: 0, groupe: .diner)
        let analyse = CalculRatioObserve.analyser(entrees: entrees)

        #expect(analyse.sections.count == 2)
        #expect(section(analyse, groupe: .petitDejeuner)?.buckets.first?.tauxBon == 1)
        #expect(section(analyse, groupe: .diner)?.buckets.first?.tauxBon == 0)
    }

    @Test("Mode ratio unique : un seul groupe, libellé « Tous les repas »")
    func modeRatioUnique() {
        let entrees = repas(tranche: .doseProche, nombre: 5, bons: 5, groupe: nil)
        let analyse = CalculRatioObserve.analyser(entrees: entrees)

        #expect(analyse.sections.count == 1)
        #expect(analyse.sections.first?.groupe == nil)
        #expect(CalculRatioObserve.libelleGroupe(nil) == "Tous les repas")
        #expect(CalculRatioObserve.libelleGroupe(.diner) == "Dîner")
    }

    @Test("Sections triées dans l'ordre de la journée, pas par libellé")
    func sectionsTriees() {
        // Entrées volontairement mélangées : le dîner d'abord, le petit
        // déjeuner en dernier.
        let entrees = repas(tranche: .doseProche, nombre: 5, bons: 1, groupe: .diner)
            + repas(tranche: .doseProche, nombre: 5, bons: 1, groupe: .enCas)
            + repas(tranche: .doseProche, nombre: 5, bons: 1, groupe: .dejeuner)
            + repas(tranche: .doseProche, nombre: 5, bons: 1, groupe: .petitDejeuner)
        let groupes = CalculRatioObserve.analyser(entrees: entrees).sections.map(\.groupe)

        #expect(groupes == [.petitDejeuner, .dejeuner, .enCas, .diner])

        // Garde-fou : l'ordre alphabétique donnerait « Déjeuner » avant
        // « Petit déjeuner », c'est exactement ce qu'on ne veut plus.
        let libelles = groupes.map { CalculRatioObserve.libelleGroupe($0) }
        #expect(libelles != libelles.sorted())
    }
}
