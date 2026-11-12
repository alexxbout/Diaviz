//
//  CalculVerdictsResucrageTests.swift
//  DiavizTests
//
//  S1 — jugement des prises de glucides pendant l'effort. L'arbre de
//  décision complet est couvert (doc Eraser « S1 — Réponse glycémique
//  sport ») : invalidations prioritaires, fenêtres, verdicts par intention,
//  regroupement en épisodes.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculVerdictsResucrageTests {

    private let bornes = BornesVerdict(hypoglycemie: 70, hyperglycemie: 180)
    private let debut = Fixtures.reference

    // MARK: - Fabriques

    private func prise(
        _ identifiant: String = "p1",
        _ intention: IntentionResucrage = .correctifHypo,
        minutes: Double = 0,
        glucides: Int = 15
    ) -> PriseAJuger {
        PriseAJuger(
            id: identifiant,
            date: Fixtures.instant(debut, plusMinutes: minutes),
            intention: intention,
            glucides: glucides
        )
    }

    private func mesures(
        _ valeurs: [Double], depuisMinutes: Double = 0, pasMinutes: Double = 5
    ) -> [PointGlycemie] {
        valeurs.enumerated().map { index, valeur in
            PointGlycemie(
                date: Fixtures.instant(debut, plusMinutes: depuisMinutes + Double(index) * pasMinutes),
                valeur: valeur
            )
        }
    }

    private func resultat(
        _ prises: [PriseAJuger],
        _ points: [PointGlycemie],
        finEffort: Date? = nil,
        correctionsInsuline: [Date] = [],
        repas: [Date] = []
    ) -> ResultatPrise {
        let resultats = CalculVerdictsResucrage.juger(
            prises: prises, points: points, bornes: bornes,
            finEffort: finEffort, correctionsInsuline: correctionsInsuline,
            repas: repas
        )
        return resultats[0]
    }

    // MARK: - Correctif hypo

    @Test("Correctif : remontée au-dessus du seuil hypo → remonté")
    func correctifRemonte() {
        let sortie = resultat([prise()], mesures([65, 80, 95, 105, 110, 115, 120]))
        #expect(sortie.verdict == .remonte)
        #expect(sortie.glycemieAvant == 65)
        #expect(sortie.glycemieApres == 120)
    }

    @Test("Correctif : dépassement de la cible haute → remonté trop haut")
    func correctifRemonteTropHaut() {
        let sortie = resultat([prise()], mesures([65, 90, 120, 160, 175, 185, 190]))
        #expect(sortie.verdict == .remonteTropHaut)
    }

    @Test("Correctif : toujours sous le seuil en fin de fenêtre → insuffisant")
    func correctifInsuffisant() {
        let sortie = resultat([prise()], mesures([60, 62, 63, 64, 65, 66, 68]))
        #expect(sortie.verdict == .insuffisant)
    }

    @Test("Correctif : glycémie finale exactement au seuil hypo → remonté")
    func correctifBorneSeuilHypo() {
        let sortie = resultat([prise()], mesures([60, 62, 64, 66, 68, 69, 70]))
        #expect(sortie.verdict == .remonte)
    }

    @Test("Correctif : maximum exactement à la cible haute → remonté")
    func correctifBorneCibleHaute() {
        let sortie = resultat([prise()], mesures([65, 100, 140, 170, 180, 175, 170]))
        #expect(sortie.verdict == .remonte)
    }

    @Test("Correctif : le creux en cours de fenêtre n'entre pas dans le verdict")
    func correctifCreuxIntermediaire() {
        // Un passage bas au milieu ne change rien tant que la fin est remontée.
        let sortie = resultat([prise()], mesures([65, 60, 58, 90, 110, 120, 125]))
        #expect(sortie.verdict == .remonte)
    }

    // MARK: - Préventif maintien

    @Test("Maintien : resté en cible sur toute la fenêtre → maintenu")
    func maintienTenu() {
        let sortie = resultat(
            [prise("p1", .preventifMaintien)], mesures([120, 118, 122, 125, 120, 119, 121])
        )
        #expect(sortie.verdict == .maintenu)
    }

    @Test("Maintien : passage sous le seuil hypo → chute non enrayée")
    func maintienChute() {
        let sortie = resultat(
            [prise("p1", .preventifMaintien)], mesures([120, 110, 90, 69, 80, 90, 100])
        )
        #expect(sortie.verdict == .chuteNonEnrayee)
    }

    @Test("Maintien : dépassement de la cible haute → monté trop haut")
    func maintienMonteTropHaut() {
        let sortie = resultat(
            [prise("p1", .preventifMaintien)], mesures([120, 140, 160, 175, 181, 180, 175])
        )
        #expect(sortie.verdict == .monteTropHaut)
    }

    @Test("Maintien : fenêtre étendue jusqu'à la fin de l'effort")
    func maintienFenetreEtendue() {
        // Creux à 45 min : visible seulement si la fenêtre suit l'effort.
        var valeurs = Array(repeating: 110.0, count: 13)   // 0 → 60 min
        valeurs[9] = 65
        let prises = [prise("p1", .preventifMaintien)]

        let avecEffort = resultat(prises, mesures(valeurs), finEffort: Fixtures.instant(debut, plusMinutes: 60))
        #expect(avecEffort.verdict == .chuteNonEnrayee)
        #expect(avecEffort.dureeFenetreMinutes == 60)
        #expect(avecEffort.libelleFenetre == "jusqu'à la fin de l'effort")

        let horsSeance = resultat(prises, mesures(valeurs))
        #expect(horsSeance.verdict == .maintenu)
        #expect(horsSeance.dureeFenetreMinutes == 30)
        #expect(horsSeance.libelleFenetre == "30 min après la prise")
    }

    @Test("Maintien : plancher de 30 min quand l'effort finit avant")
    func maintienPlancher() {
        let sortie = resultat(
            [prise("p1", .preventifMaintien)],
            mesures([120, 118, 122, 125, 120, 119, 121]),
            finEffort: Fixtures.instant(debut, plusMinutes: 10)
        )
        #expect(sortie.dureeFenetreMinutes == 30)
        #expect(sortie.libelleFenetre == "30 min après la prise")
    }

    @Test("La fin d'effort n'étend que le préventif maintien")
    func finEffortIgnoreeHorsMaintien() {
        let sortie = resultat(
            [prise("p1", .correctifHypo)],
            mesures(Array(repeating: 110.0, count: 13)),
            finEffort: Fixtures.instant(debut, plusMinutes: 60)
        )
        #expect(sortie.dureeFenetreMinutes == 30)
        #expect(sortie.libelleFenetre == "30 min après la prise")
    }

    // MARK: - Préventif anti-chute

    @Test("Anti-chute : aucune hypo sur la fenêtre → chute évitée")
    func antiChuteEvitee() {
        let sortie = resultat(
            [prise("p1", .preventifAntiChute)], mesures([120, 118, 115, 110, 105, 100, 98])
        )
        #expect(sortie.verdict == .chuteEvitee)
    }

    @Test("Anti-chute : passage sous le seuil hypo → chute non enrayée")
    func antiChuteNonEnrayee() {
        let sortie = resultat(
            [prise("p1", .preventifAntiChute)], mesures([120, 110, 90, 69, 80, 90, 100])
        )
        #expect(sortie.verdict == .chuteNonEnrayee)
    }

    @Test("Anti-chute : dépassement de la cible haute → monté trop haut")
    func antiChuteMonteTropHaut() {
        let sortie = resultat(
            [prise("p1", .preventifAntiChute)], mesures([120, 140, 160, 175, 190, 180, 175])
        )
        #expect(sortie.verdict == .monteTropHaut)
    }

    // MARK: - Invalidations

    @Test("Correction d'insuline dans la fenêtre → non évaluable")
    func correctionInsulineInvalide() {
        let sortie = resultat(
            [prise()], mesures([65, 80, 95, 105, 110, 115, 120]),
            correctionsInsuline: [Fixtures.instant(debut, plusMinutes: 10)]
        )
        #expect(sortie.verdict == .nonEvaluable)
        #expect(sortie.raison == .correctionInsuline)
        #expect(sortie.glycemieApres == nil)
    }

    @Test("La correction d'insuline prime sur toutes les autres invalidations")
    func correctionInsulinePrioritaire() {
        // Préventif suivi d'un correctif : sans insuline ce serait « chute non
        // enrayée » — l'injection rend le tout ininterprétable.
        let prises = [
            prise("p1", .preventifMaintien),
            prise("p2", .correctifHypo, minutes: 15)
        ]
        let sortie = resultat(
            prises, mesures([120, 100, 80, 68, 75, 85, 95]),
            correctionsInsuline: [Fixtures.instant(debut, plusMinutes: 5)]
        )
        #expect(sortie.verdict == .nonEvaluable)
        #expect(sortie.raison == .correctionInsuline)
    }

    @Test("Correction aux bornes de la fenêtre : n'invalide pas")
    func correctionAuxBornes() {
        let points = mesures([65, 80, 95, 105, 110, 115, 120])
        let auDepart = resultat([prise()], points, correctionsInsuline: [debut])
        #expect(auDepart.verdict == .remonte)

        let aLaFin = resultat(
            [prise()], points, correctionsInsuline: [Fixtures.instant(debut, plusMinutes: 30)]
        )
        #expect(aLaFin.verdict == .remonte)
    }

    @Test("Repas pris dans l'heure précédant la prise → non évaluable")
    func repasAvantInvalide() {
        let sortie = resultat(
            [prise()], mesures([65, 80, 95, 105, 110, 115, 120]),
            repas: [Fixtures.instant(debut, plusMinutes: -45)]
        )
        #expect(sortie.verdict == .nonEvaluable)
        #expect(sortie.raison == .repasProche)
        #expect(sortie.glycemieApres == nil)
    }

    @Test("Repas pendant la fenêtre → non évaluable")
    func repasPendantInvalide() {
        let sortie = resultat(
            [prise()], mesures([65, 80, 95, 105, 110, 115, 120]),
            repas: [Fixtures.instant(debut, plusMinutes: 15)]
        )
        #expect(sortie.raison == .repasProche)
    }

    @Test("Repas plus d'une heure avant, ou après la fenêtre : n'invalide pas")
    func repasHorsMarge() {
        let points = mesures([65, 80, 95, 105, 110, 115, 120])
        let avant = resultat([prise()], points, repas: [Fixtures.instant(debut, plusMinutes: -61)])
        #expect(avant.verdict == .remonte)
        let apres = resultat([prise()], points, repas: [Fixtures.instant(debut, plusMinutes: 30)])
        #expect(apres.verdict == .remonte)
    }

    @Test("La correction d'insuline prime sur le repas proche")
    func correctionPrimeSurRepas() {
        let sortie = resultat(
            [prise()], mesures([65, 80, 95, 105, 110, 115, 120]),
            correctionsInsuline: [Fixtures.instant(debut, plusMinutes: 10)],
            repas: [Fixtures.instant(debut, plusMinutes: -20)]
        )
        #expect(sortie.raison == .correctionInsuline)
    }

    @Test("Un repas proche masque la chute non enrayée d'un préventif")
    func repasPrimeSurChuteNonEnrayee() {
        let prises = [
            prise("p1", .preventifMaintien),
            prise("p2", .correctifHypo, minutes: 15)
        ]
        let sortie = resultat(
            prises, mesures([120, 100, 80, 68, 75, 85, 95]),
            repas: [Fixtures.instant(debut, plusMinutes: -10)]
        )
        #expect(sortie.verdict == .nonEvaluable)
        #expect(sortie.raison == .repasProche)
    }

    @Test("Prise suivante dans la fenêtre → non évaluable")
    func priseSuivanteInvalide() {
        let prises = [prise("p1"), prise("p2", minutes: 15)]
        let sortie = resultat(prises, mesures([65, 80, 95, 105, 110, 115, 120]))
        #expect(sortie.verdict == .nonEvaluable)
        #expect(sortie.raison == .priseSuivante)
        #expect(sortie.glycemieApres == nil)
    }

    @Test("Préventif suivi d'un correctif hypo → chute non enrayée, pas un silence")
    func preventifSuiviDunCorrectif() {
        let prises = [
            prise("p1", .preventifMaintien),
            prise("p2", .correctifHypo, minutes: 15)
        ]
        let sortie = resultat(prises, mesures([120, 100, 80, 68, 75, 85, 95]))

        #expect(sortie.verdict == .chuteNonEnrayee)
        #expect(sortie.raison == nil)
        #expect(sortie.libelleFenetre == "jusqu'au resucrage suivant")
        #expect(sortie.dureeFenetreMinutes == 15)
        #expect(sortie.glycemieApres == 68)   // mesure au moment du correctif
    }

    @Test("Prise suivante hors fenêtre → jugement normal")
    func priseSuivanteHorsFenetre() {
        let prises = [prise("p1"), prise("p2", minutes: 35)]
        let sortie = resultat(prises, mesures([65, 80, 95, 105, 110, 115, 120]))
        #expect(sortie.verdict == .remonte)
    }

    @Test("Moins de 3 mesures sur la fenêtre → indéterminé")
    func mesuresInsuffisantes() {
        let sortie = resultat([prise()], mesures([65, 80]))
        #expect(sortie.verdict == .indetermine)
        #expect(sortie.raison == .mesuresInsuffisantes)
        #expect(sortie.glycemieApres == nil)
    }

    @Test("Exactement 3 mesures sur la fenêtre → jugement possible")
    func troisMesuresSuffisent() {
        let sortie = resultat([prise()], mesures([65, 80, 95]))
        #expect(sortie.verdict == .remonte)
    }

    @Test("Aucune mesure → indéterminé, sans glycémie de départ")
    func aucuneMesure() {
        let sortie = resultat([prise()], [])
        #expect(sortie.verdict == .indetermine)
        #expect(sortie.glycemieAvant == nil)
        #expect(sortie.tendanceAvant == nil)
    }

    // MARK: - Épisodes

    @Test("Deux prises rapprochées de même intention → un seul épisode")
    func episodeUnique() {
        let episodes = CalculVerdictsResucrage.decouperEnEpisodes([
            prise("p1"), prise("p2", minutes: 20)
        ])
        #expect(episodes["p1"] == 0)
        #expect(episodes["p2"] == 0)
    }

    @Test("Écart exactement égal au délai de jugement → nouvel épisode")
    func episodeBorneDuDelai() {
        let episodes = CalculVerdictsResucrage.decouperEnEpisodes([
            prise("p1"), prise("p2", minutes: 30)
        ])
        #expect(episodes["p2"] == 1)

        let serrees = CalculVerdictsResucrage.decouperEnEpisodes([
            prise("p1"), prise("p2", minutes: 29)
        ])
        #expect(serrees["p2"] == 0)
    }

    @Test("Changement d'intention → nouvel épisode, même rapproché")
    func episodeChangementIntention() {
        let episodes = CalculVerdictsResucrage.decouperEnEpisodes([
            prise("p1", .preventifMaintien), prise("p2", .correctifHypo, minutes: 5)
        ])
        #expect(episodes["p1"] == 0)
        #expect(episodes["p2"] == 1)
    }

    @Test("Trois prises enchaînées de même intention → un épisode commun")
    func episodeDeTroisPrises() {
        let episodes = CalculVerdictsResucrage.decouperEnEpisodes([
            prise("p1"), prise("p2", minutes: 20), prise("p3", minutes: 40)
        ])
        #expect(Set(episodes.values) == [0])
    }

    @Test("Épisode reporté sur chaque résultat")
    func episodeReporteSurLesResultats() {
        let resultats = CalculVerdictsResucrage.juger(
            prises: [prise("p1"), prise("p2", minutes: 45)],
            points: mesures(Array(repeating: 100.0, count: 20)),
            bornes: bornes, finEffort: nil
        )
        #expect(resultats.map(\.idEpisode) == [0, 1])
    }

    // MARK: - Lecture des mesures

    @Test("Glycémie de départ : mesure la plus proche dans les 10 min")
    func glycemieAvantTolerance() {
        // Mesure isolée à −10 min pile : retenue comme glycémie de départ.
        let auxDixMinutes = resultat([prise()], mesures([88], depuisMinutes: -10))
        #expect(auxDixMinutes.glycemieAvant == 88)

        // Mesure isolée à +15 min : trop loin, aucune glycémie de départ.
        let tropLoin = resultat([prise()], mesures([90], depuisMinutes: 15))
        #expect(tropLoin.glycemieAvant == nil)
    }

    @Test("Tendance avant la prise : baisse, hausse ou stable selon ±10 mg/dL")
    func tendanceAvantPrise() {
        let baisse = resultat([prise()], mesures([120, 115, 110, 105, 110, 115, 120], depuisMinutes: -15))
        #expect(baisse.tendanceAvant == .baisse)

        let hausse = resultat([prise()], mesures([100, 105, 110, 115, 120, 125, 130], depuisMinutes: -15))
        #expect(hausse.tendanceAvant == .hausse)

        let stable = resultat([prise()], mesures([100, 102, 104, 105, 110, 115, 120], depuisMinutes: -15))
        #expect(stable.tendanceAvant == .stable)
    }

    @Test("Tendance : bornes exactes de ±10 mg/dL")
    func tendanceBornesExactes() {
        let dixEnBaisse = resultat([prise()], mesures([110, 105, 102, 100, 105, 110, 115], depuisMinutes: -15))
        #expect(dixEnBaisse.tendanceAvant == .baisse)

        let neufEnBaisse = resultat([prise()], mesures([109, 105, 102, 100, 105, 110, 115], depuisMinutes: -15))
        #expect(neufEnBaisse.tendanceAvant == .stable)
    }

    @Test("Une seule mesure avant la prise → tendance inconnue")
    func tendanceIndisponible() {
        let sortie = resultat([prise()], mesures([100, 105, 110, 115]))
        #expect(sortie.tendanceAvant == nil)
    }

    // MARK: - Entrées

    @Test("Aucune prise → aucun résultat")
    func aucunePrise() {
        let resultats = CalculVerdictsResucrage.juger(
            prises: [], points: mesures([100, 105, 110]), bornes: bornes, finEffort: nil
        )
        #expect(resultats.isEmpty)
    }

    @Test("Prises fournies dans le désordre : triées avant jugement")
    func prisesDesordonnees() {
        let resultats = CalculVerdictsResucrage.juger(
            prises: [prise("p2", minutes: 45), prise("p1")],
            points: mesures(Array(repeating: 100.0, count: 20)),
            bornes: bornes, finEffort: nil
        )
        #expect(resultats.map(\.id) == ["p1", "p2"])
    }
}
