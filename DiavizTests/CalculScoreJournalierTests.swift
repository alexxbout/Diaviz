//
//  CalculScoreJournalierTests.swift
//  DiavizTests
//
//  Score quotidien = 100 − GRI (Klonoff 2022). Les tests portent sur les
//  règles qui décident d'un chiffre affiché sur l'accueil : seuil de
//  couverture, bornes exactes des bandes glycémiques, pondération GRI et
//  découpage des épisodes d'hypoglycémie.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculScoreJournalierTests {

    // MARK: - Couverture (dégradation gracieuse)

    @Test("Aucune lecture dans la fenêtre → pas de score")
    func aucuneLecture() {
        let fenetre = Fixtures.reference...Fixtures.instant(plusHeures: 24)
        #expect(CalculScoreJournalier.faits(depuis: [], fenetre: fenetre) == nil)
    }

    @Test("Lectures toutes hors fenêtre → pas de score")
    func lecturesHorsFenetre() {
        let lectures = Fixtures.seriePlate(
            depuis: Fixtures.instant(plusHeures: 30), valeur: 110, nombre: 300
        )
        let fenetre = Fixtures.reference...Fixtures.instant(plusHeures: 24)
        #expect(CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre) == nil)
    }

    /// Fenêtre de 100 min → 20 échantillons attendus ; 14 présents = 0,70 pile.
    @Test("Couverture exactement au seuil → score produit")
    func couvertureAuSeuilExact() {
        let lectures = Fixtures.seriePlate(valeur: 110, nombre: 14)
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 100)
        #expect(CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre) != nil)
    }

    @Test("Couverture juste sous le seuil → pas de score")
    func couvertureJusteSousLeSeuil() {
        let lectures = Fixtures.seriePlate(valeur: 110, nombre: 13)
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 100)
        #expect(CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre) == nil)
    }

    @Test("Seuil de couverture paramétrable")
    func couvertureParametrable() {
        let lectures = Fixtures.seriePlate(valeur: 110, nombre: 13)
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 100)
        #expect(CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre, couvertureMin: 0.65) != nil)
    }

    // MARK: - Score et bandes

    @Test("Journée entièrement en cible → score 100, TIR 100 %")
    func journeeParfaite() {
        let lectures = Fixtures.seriePlate(valeur: 110, nombre: 12)
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 55)
        let faits = CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre)

        #expect(faits?.score == 100)
        #expect(faits?.tir == 100)
        #expect(faits?.tbrLevel1 == 0)
        #expect(faits?.tbrLevel2 == 0)
        #expect(faits?.tarLevel1 == 0)
        #expect(faits?.tarLevel2 == 0)
    }

    /// Une valeur par bande, aux bornes exactes : 53/54 (TBR2 vs TBR1),
    /// 69/70 (TBR1 vs cible), 180/181 (cible vs TAR1), 250/251 (TAR1 vs TAR2).
    @Test("Bornes exactes des bandes glycémiques")
    func bornesDesBandes() {
        let lectures = Fixtures.serie(valeurs: [53, 54, 69, 70, 180, 181, 250, 251])
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 35)
        let faits = CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre)

        #expect(faits?.tbrLevel2 == 12.5)   // 53
        #expect(faits?.tbrLevel1 == 25)     // 54, 69
        #expect(faits?.tir == 25)           // 70, 180
        #expect(faits?.tarLevel1 == 25)     // 181, 250
        #expect(faits?.tarLevel2 == 12.5)   // 251
    }

    @Test("Score borné à 0 quand le GRI dépasse 100")
    func scoreBorneAZero() {
        // GRI = 3×12,5 + 2,4×25 + 1,6×12,5 + 0,8×25 = 137,5 → 100 − GRI < 0.
        let lectures = Fixtures.serie(valeurs: [53, 54, 69, 70, 180, 181, 250, 251])
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 35)
        #expect(CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre)?.score == 0)
    }

    @Test("Pondération GRI : 50 % au-dessus de 250 → score 20")
    func ponderationGRI() {
        // GRI = 1,6 × 50 = 80 → score 20.
        let lectures = Fixtures.serie(valeurs: [300, 300, 300, 300, 100, 100, 100, 100])
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 35)
        #expect(CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre)?.score == 20)
    }

    @Test("Ordre des lectures en entrée indifférent")
    func ordreIndifferent() {
        let lectures = Fixtures.serie(valeurs: [53, 54, 69, 70, 180, 181, 250, 251])
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 35)

        let ordonne = CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre)
        let melange = CalculScoreJournalier.faits(depuis: lectures.reversed(), fenetre: fenetre)
        #expect(ordonne == melange)
    }

    @Test("Pic = valeur maximale de la fenêtre, avec son horodatage")
    func picDeLaFenetre() {
        let lectures = Fixtures.serie(valeurs: [110, 140, 210, 160, 120, 115, 118, 121])
        let fenetre = Fixtures.reference...Fixtures.instant(plusMinutes: 35)
        let faits = CalculScoreJournalier.faits(depuis: lectures, fenetre: fenetre)

        #expect(faits?.peakValue == 210)
        #expect(faits?.peakTime != nil)
    }

    // MARK: - Comptage des épisodes d'hypoglycémie

    @Test("Aucune valeur sous le seuil → aucun épisode")
    func aucuneHypo() {
        let comptage = CalculScoreJournalier.comptageHypos([110, 90, 70, 200])
        #expect(comptage.hypo == 0)
        #expect(comptage.severe == 0)
    }

    @Test("70 n'est pas une hypo, 69 en est une")
    func borneSeuilHypo() {
        #expect(CalculScoreJournalier.comptageHypos([70]).hypo == 0)
        #expect(CalculScoreJournalier.comptageHypos([69]).hypo == 1)
    }

    @Test("54 n'est pas une hypo sévère, 53 en est une")
    func borneSeuilSevere() {
        let limite = CalculScoreJournalier.comptageHypos([54])
        #expect(limite.hypo == 1)
        #expect(limite.severe == 0)

        let severe = CalculScoreJournalier.comptageHypos([53])
        #expect(severe.hypo == 1)
        #expect(severe.severe == 1)
    }

    @Test("Points contigus sous le seuil = un seul épisode")
    func episodeContigu() {
        let comptage = CalculScoreJournalier.comptageHypos([110, 65, 60, 58, 62, 110])
        #expect(comptage.hypo == 1)
    }

    @Test("Retour en cible entre deux passages bas = deux épisodes")
    func deuxEpisodesSepares() {
        let comptage = CalculScoreJournalier.comptageHypos([65, 110, 60])
        #expect(comptage.hypo == 2)
    }

    @Test("Un épisode sévère n'est compté qu'une fois, même avec plusieurs points < 54")
    func severeComptéUneFois() {
        let comptage = CalculScoreJournalier.comptageHypos([50, 48, 45, 110])
        #expect(comptage.hypo == 1)
        #expect(comptage.severe == 1)
    }

    @Test("Deux épisodes sévères distincts sont comptés séparément")
    func deuxEpisodesSeveres() {
        let comptage = CalculScoreJournalier.comptageHypos([50, 110, 45])
        #expect(comptage.hypo == 2)
        #expect(comptage.severe == 2)
    }

    @Test("Série vide → aucun épisode")
    func serieVide() {
        let comptage = CalculScoreJournalier.comptageHypos([])
        #expect(comptage.hypo == 0)
        #expect(comptage.severe == 0)
    }
}
