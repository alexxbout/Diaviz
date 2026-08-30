//
//  CalculHyposCoucherTests.swift
//  DiavizTests
//
//  B2/B3 — fusion des soirs et métriques comptées de la page « Hypos au
//  coucher ». Le mining de situations a été retiré en août 2026 : la page
//  n'expose plus que des faits recomptables (hypos, dont avec rechute, hypos
//  évitées par un préventif et leurs glucides typiques).
//

import Foundation
import Testing
@testable import Diaviz

struct CalculHyposCoucherTests {

    // MARK: - Fabriques

    private func nuitB2(
        jour: Double = 0,
        glycemie: Int = 95,
        issue: IssueEndormissement,
        rechute: Bool = false
    ) -> NuitEndormissement {
        NuitEndormissement(
            id: UUID(),
            date: Fixtures.instant(plusHeures: jour * 24),
            glycemieCoucher: glycemie,
            tendance: .stable,
            glucides: nil, sport: nil, iob: nil, charge: .aucune,
            issue: issue,
            rechute: rechute
        )
    }

    private func analyse(
        _ nuits: [NuitEndormissement],
        corrections: [CorrectionSoir] = [],
        timeline: [NuitTimeline] = []
    ) -> AnalyseHyposCoucher {
        CalculHyposCoucher.analyser(
            endormissement: AnalyseEndormissement(seuilCoucher: 160, doseActuelle: 18, nuits: nuits),
            corrections: AnalyseCorrections(corrections: corrections),
            timeline: timeline
        )
    }

    // MARK: - Fusion B2 + B3

    @Test("Fusion : soirs B2 et B3 réunis, triés du plus récent au plus ancien")
    func fusionDesDeuxPopulations() {
        let jour = Fixtures.reference
        let b3 = CorrectionSoir(
            id: UUID(), date: jour.addingTimeInterval(24 * 3600), glycemie: 210,
            tendance: .hausse, glucides: nil, dose: 3, iob: nil, sport: nil,
            charge: .aucune, issue: .surCorrection
        )

        let resultat = analyse(
            [nuitB2(issue: .hypo(delaiMinutes: 80))],
            corrections: [b3]
        )

        #expect(resultat.totalSoirs == 2)
        #expect(resultat.totalHypos == 2)
        #expect(resultat.doseActuelle == 18)
        #expect(resultat.seuilCoucher == 160)
        #expect(resultat.soirs.first?.glycemie == 210)          // le plus récent d'abord
        #expect(resultat.soirs.first?.correction == 3)
        #expect(resultat.soirs.last?.delaiHypoMinutes == 80)
    }

    @Test("Une correction « insuffisante » n'est pas une hypo")
    func correctionInsuffisanteHorsFocusHypo() {
        let b3 = CorrectionSoir(
            id: UUID(), date: Fixtures.reference, glycemie: 240, tendance: .stable,
            glucides: nil, dose: 2, iob: nil, sport: nil, charge: .aucune, issue: .insuffisant
        )
        let resultat = analyse([], corrections: [b3])

        #expect(resultat.totalSoirs == 1)
        #expect(resultat.totalHypos == 0)
        #expect(resultat.soirs.first?.issueCorrection == .insuffisant)
    }

    @Test("Catégorie B1 reprise de la timeline pour la nuit correspondante")
    func categorieB1DepuisTimeline() {
        let cal = Calendar.current
        let nuits = [nuitB2(issue: .stable)]
        let timeline = [
            NuitTimeline(date: cal.startOfDay(for: Fixtures.reference),
                         etat: .valide(categorie: .tendanceBasse), avantChangementDose: false)
        ]

        #expect(analyse(nuits, timeline: timeline).soirs.first?.categorieB1 == .tendanceBasse)
        #expect(analyse(nuits).soirs.first?.categorieB1 == nil)
    }

    @Test("Nuit B1 exclue → aucune catégorie reprise")
    func nuitB1Exclue() {
        let cal = Calendar.current
        let timeline = [
            NuitTimeline(date: cal.startOfDay(for: Fixtures.reference),
                         etat: .exclue(raison: .cgmIncomplet), avantChangementDose: false)
        ]
        #expect(analyse([nuitB2(issue: .stable)], timeline: timeline).soirs.first?.categorieB1 == nil)
    }

    // MARK: - Métriques comptées

    @Test("Une hypo évitée n'est ni une hypo ni un soir stable")
    func hypoEviteeHorsCompteurHypos() {
        let resultat = analyse([
            nuitB2(jour: 0, issue: .hypo(delaiMinutes: 40)),
            nuitB2(jour: 1, issue: .hypoEvitee(glucides: 15)),
            nuitB2(jour: 2, issue: .stable),
        ])

        #expect(resultat.totalSoirs == 3)
        #expect(resultat.totalHypos == 1)
        #expect(resultat.totalHyposEvitees == 1)
        // Le soir évité n'est pas compté en hypo : les deux totaux ne
        // s'additionnent jamais pour retrouver le nombre de soirs à problème.
        let hyposEviteesDansLesHypos = resultat.soirsEnHypo.filter(\.hypoEvitee)
        #expect(hyposEviteesDansLesHypos.isEmpty)
    }

    @Test("Les rechutes sont un sous-ensemble des hypos, jamais un total à part")
    func rechutesSousEnsembleDesHypos() {
        let resultat = analyse([
            nuitB2(jour: 0, issue: .hypo(delaiMinutes: 40), rechute: true),
            nuitB2(jour: 1, issue: .hypo(delaiMinutes: 55)),
            nuitB2(jour: 2, issue: .stable),
        ])

        #expect(resultat.totalHypos == 2)
        #expect(resultat.totalRechutes == 1)
        let rechutesHorsHypo = resultat.soirsAvecRechute.filter { !$0.enHypo }
        #expect(rechutesHorsHypo.isEmpty)
    }

    @Test("Une rechute portée par une sur-correction B3 est comptée")
    func rechuteCoteCorrections() {
        let b3 = CorrectionSoir(
            id: UUID(), date: Fixtures.reference, glycemie: 220, tendance: .hausse,
            glucides: nil, dose: 4, iob: nil, sport: nil, charge: .aucune,
            issue: .surCorrection, rechute: true
        )
        let resultat = analyse([], corrections: [b3])

        #expect(resultat.totalHypos == 1)
        #expect(resultat.totalRechutes == 1)
    }

    @Test("Glucides typiques = médiane des préventifs qui ont tenu")
    func glucidesMedians() {
        let resultat = analyse([
            nuitB2(jour: 0, issue: .hypoEvitee(glucides: 10)),
            nuitB2(jour: 1, issue: .hypoEvitee(glucides: 15)),
            // Valeur extrême : une moyenne donnerait ~28 g, un chiffre que
            // l'utilisateur n'a jamais pris. La médiane tient bon.
            nuitB2(jour: 2, issue: .hypoEvitee(glucides: 60)),
        ])

        #expect(resultat.totalHyposEvitees == 3)
        #expect(resultat.glucidesTypiquesHypoEvitee == 15)
    }

    @Test("Aucun préventif → pas de glucides typiques")
    func pasDeGlucidesTypiquesSansPreventif() {
        let resultat = analyse([nuitB2(issue: .hypo(delaiMinutes: 30))])
        #expect(resultat.glucidesTypiquesHypoEvitee == nil)
        #expect(resultat.totalHyposEvitees == 0)
    }

    @Test("Hub vide → toutes les métriques à zéro, aucun crash")
    func hubVide() {
        let resultat = analyse([])
        #expect(resultat.totalSoirs == 0)
        #expect(resultat.totalHypos == 0)
        #expect(resultat.totalRechutes == 0)
        #expect(resultat.totalHyposEvitees == 0)
        #expect(resultat.glucidesTypiquesHypoEvitee == nil)
    }
}

// MARK: - Détection de rechute

/// La rechute a **une seule** définition dans l'app (`DetectionRechute` délègue
/// à B1) : resucrage correctif pendant un épisode hypo, puis nouvel épisode
/// moins de 60 min après.
struct DetectionRechuteTests {

    private let seuil = 70

    private func lectures(
        _ valeurs: [Int], pasMinutes: Double = 5
    ) -> [(date: Date, valeur: Int, tendance: TendanceGlycemie?)] {
        Fixtures.serie(valeurs: valeurs, pasMinutes: pasMinutes)
            .map { (date: $0.date, valeur: $0.valeur, tendance: nil) }
    }

    @Test("Hypo → resucrage correctif → nouvelle hypo dans l'heure = rechute")
    func rechuteDetectee() {
        // 2 pas bas, remontée, 2 pas bas à nouveau ~25 min plus tard.
        let serie = lectures([65, 62, 95, 110, 105, 68, 64, 90])
        let resucrage = [(heure: Fixtures.instant(plusMinutes: 5), glucides: 15,
                          intention: IntentionResucrage.correctifHypo)]

        #expect(DetectionRechute.rechute(
            lectures: serie, resucrages: resucrage,
            de: Fixtures.reference, seuilHypo: seuil
        ))
    }

    @Test("Sans resucrage correctif entre les deux, ce sont des hypos en série")
    func serieNestPasUneRechute() {
        let serie = lectures([65, 62, 95, 110, 105, 68, 64, 90])
        #expect(DetectionRechute.rechute(
            lectures: serie, resucrages: [],
            de: Fixtures.reference, seuilHypo: seuil
        ) == false)
    }

    @Test("Un resucrage préventif ne peut pas produire de rechute")
    func preventifJamaisUneRechute() {
        let serie = lectures([65, 62, 95, 110, 105, 68, 64, 90])
        let preventif = [(heure: Fixtures.instant(plusMinutes: 5), glucides: 15,
                          intention: IntentionResucrage.preventifAntiChute)]

        #expect(DetectionRechute.rechute(
            lectures: serie, resucrages: preventif,
            de: Fixtures.reference, seuilHypo: seuil
        ) == false)
    }

    @Test("Un seul épisode hypo, si bien corrigé, n'est pas une rechute")
    func episodeUniqueSansRechute() {
        let serie = lectures([65, 62, 95, 110, 120, 118])
        let resucrage = [(heure: Fixtures.instant(plusMinutes: 5), glucides: 15,
                          intention: IntentionResucrage.correctifHypo)]

        #expect(DetectionRechute.rechute(
            lectures: serie, resucrages: resucrage,
            de: Fixtures.reference, seuilHypo: seuil
        ) == false)
    }

    @Test("Aucune mesure dans la fenêtre → pas de rechute affirmée")
    func sansCgmPasDeRechute() {
        #expect(DetectionRechute.rechute(
            lectures: [], resucrages: [],
            de: Fixtures.reference, seuilHypo: seuil
        ) == false)
    }
}
