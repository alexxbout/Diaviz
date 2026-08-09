//
//  CalculAnalyseEndormissementTests.swift
//  DiavizTests
//
//  B2 — hypos à l'endormissement. Ce qui compte ici est la **population**
//  retenue : frontière avec B3 (correction au coucher), seuil de coucher,
//  mode pause, fenêtre comparable depuis le changement de dose.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculAnalyseEndormissementTests {

    private let jour = Fixtures.reference
    /// Lente prise à J+22h — toutes les zones se déduisent de cet instant.
    private var lente: Date { Fixtures.instant(jour, plusHeures: 22) }

    // MARK: - Fabriques

    private func ancrage(glycemieCoucher: Int = 110, doseLente: Double = 18) -> AncrageNuit {
        AncrageNuit(
            dateNuit: jour, basaleTime: lente,
            doseLente: doseLente, glycemieCoucher: glycemieCoucher
        )
    }

    /// Mesures régulières couvrant la zone 2 (lente → lente + 2h).
    private func lecturesZone2(
        _ valeurs: [Int]
    ) -> [(date: Date, valeur: Int, tendance: TendanceGlycemie?)] {
        valeurs.enumerated().map { index, valeur in
            (date: lente.addingTimeInterval(Double(index) * 10 * 60), valeur: valeur, tendance: .stable)
        }
    }

    private func entrees(
        nuits: [AncrageNuit]? = nil,
        lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)] = [],
        rapides: [(heure: Date, dose: Double, correction: Bool)] = [],
        repas: [(heure: Date, glucides: Int)] = [],
        sports: [(debut: Date, resume: SportResume)] = [],
        pauses: [(debut: Date, fin: Date?)] = []
    ) -> EntreesEndormissement {
        EntreesEndormissement(
            nuits: nuits ?? [ancrage()], lectures: lectures,
            rapides: rapides, repas: repas, sports: sports, pauses: pauses
        )
    }

    private func analyser(
        _ entrees: EntreesEndormissement, changementDoseRecent: Date? = nil
    ) -> AnalyseEndormissement {
        CalculAnalyseEndormissement.analyser(
            entrees: entrees, doseActuelle: 18, changementDoseRecent: changementDoseRecent
        )
    }

    // MARK: - Population retenue

    @Test("Nuit sans lente enregistrée → hors analyse")
    func nuitSansLente() {
        let analyse = analyser(entrees(
            nuits: [ancrage(doseLente: 0)], lectures: lecturesZone2([110, 108, 105])
        ))
        #expect(analyse.nuits.isEmpty)
    }

    @Test("Coucher au-dessus du seuil → hors population B2")
    func coucherAuDessusDuSeuil() {
        let analyse = analyser(entrees(
            nuits: [ancrage(glycemieCoucher: 160)], lectures: lecturesZone2([160, 155, 150])
        ))
        #expect(analyse.nuits.isEmpty)
    }

    @Test("Coucher juste sous le seuil → retenu")
    func coucherJusteSousLeSeuil() {
        let analyse = analyser(entrees(
            nuits: [ancrage(glycemieCoucher: 159)], lectures: lecturesZone2([159, 155, 150])
        ))
        #expect(analyse.nuits.count == 1)
    }

    @Test("Correction rapide au coucher → la soirée relève de B3, pas de B2")
    func frontiereAvecB3() {
        let correction = (heure: Fixtures.instant(jour, plusHeures: 21), dose: 2.0, correction: true)
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 95]), rapides: [correction]))
        #expect(analyse.nuits.isEmpty)
    }

    @Test("Bolus rapide non correctif au coucher → la nuit reste dans B2")
    func bolusNonCorrectifConserve() {
        let bolus = (heure: Fixtures.instant(jour, plusHeures: 21), dose: 6.0, correction: false)
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 95]), rapides: [bolus]))
        #expect(analyse.nuits.count == 1)
    }

    @Test("Mode pause sur la fenêtre de coucher → nuit exclue")
    func modePause() {
        let pause = (debut: Fixtures.instant(jour, plusHeures: 12), fin: Optional(Fixtures.instant(jour, plusHeures: 30)))
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 95]), pauses: [pause]))
        #expect(analyse.nuits.isEmpty)
    }

    @Test("Pause ouverte (sans fin) couvrant le coucher → nuit exclue")
    func pauseOuverte() {
        let pause = (debut: Fixtures.instant(jour, plusHeures: 12), fin: Date?.none)
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 95]), pauses: [pause]))
        #expect(analyse.nuits.isEmpty)
    }

    @Test("Nuit antérieure au changement de dose → hors fenêtre comparable")
    func fenetreDepuisChangementDeDose() {
        let apres = Fixtures.instant(jour, plusHeures: 48)
        let analyse = analyser(
            entrees(lectures: lecturesZone2([110, 100, 95])), changementDoseRecent: apres
        )
        #expect(analyse.nuits.isEmpty)
    }

    @Test("Nuit du jour même du changement de dose → conservée")
    func nuitDuJourDuChangement() {
        let analyse = analyser(
            entrees(lectures: lecturesZone2([110, 100, 95])),
            changementDoseRecent: Fixtures.instant(jour, plusHeures: 6)
        )
        #expect(analyse.nuits.count == 1)
    }

    // MARK: - Issue

    @Test("Aucune mesure sous le seuil hypo → issue stable")
    func issueStable() {
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 95, 90, 88])))
        #expect(analyse.nuits.first?.issue == .stable)
        #expect(analyse.nombreHypos == 0)
    }

    @Test("Première mesure sous le seuil → hypo, délai compté depuis la lente")
    func issueHypoAvecDelai() {
        // Pas de 10 min : la 5ᵉ mesure tombe 40 min après la lente.
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 90, 80, 65, 60])))
        #expect(analyse.nuits.first?.issue == .hypo(delaiMinutes: 40))
        #expect(analyse.nombreHypos == 1)
    }

    @Test("Mesure exactement au seuil hypo → pas une hypo")
    func issueBorneDuSeuilHypo() {
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 70])))
        #expect(analyse.nuits.first?.issue == .stable)
    }

    @Test("Hypo hors zone d'endormissement (au-delà de 2h) → ignorée")
    func hypoHorsZone2() {
        var lectures = lecturesZone2([110, 105, 100])
        lectures.append((date: lente.addingTimeInterval(3 * 3600), valeur: 55, tendance: .baisse))
        #expect(analyser(entrees(lectures: lectures)).nuits.first?.issue == .stable)
    }

    // MARK: - Contexte

    @Test("Glucides autour du coucher sommés, absents sinon")
    func glucidesAutourDuCoucher() {
        let repas = [
            (heure: Fixtures.instant(jour, plusHeures: 20), glucides: 30),
            (heure: lente.addingTimeInterval(30 * 60), glucides: 15)
        ]
        let avec = analyser(entrees(lectures: lecturesZone2([110, 100, 95]), repas: repas))
        #expect(avec.nuits.first?.glucides == 45)

        let sans = analyser(entrees(lectures: lecturesZone2([110, 100, 95])))
        #expect(sans.nuits.first?.glucides == nil)
    }

    @Test("Sport du jour même repris en contexte")
    func sportDuJour() {
        let seance = (
            debut: Fixtures.instant(jour, plusHeures: 12),
            resume: SportResume(type: "Course", intensite: "modéré", dureeMinutes: 45)
        )
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 95]), sports: [seance]))
        #expect(analyse.nuits.first?.sport?.type == "Course")
    }

    @Test("IOB résiduel négligeable → non affiché")
    func iobNegligeable() {
        // Injection largement au-delà de la DIA (4h) : plus rien d'actif.
        let vieille = (heure: Fixtures.instant(jour, plusHeures: 10), dose: 8.0, correction: false)
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 95]), rapides: [vieille]))
        #expect(analyse.nuits.first?.iob == nil)
    }

    @Test("IOB résiduel significatif → renseigné")
    func iobSignificatif() {
        let recente = (heure: lente.addingTimeInterval(-3600), dose: 6.0, correction: false)
        let analyse = analyser(entrees(lectures: lecturesZone2([110, 100, 95]), rapides: [recente]))
        #expect((analyse.nuits.first?.iob ?? 0) > 0.05)
    }

    @Test("Nuits triées par glycémie de coucher croissante")
    func triParGlycemie() {
        let nuits = [
            AncrageNuit(dateNuit: jour, basaleTime: lente, doseLente: 18, glycemieCoucher: 140),
            AncrageNuit(dateNuit: Fixtures.instant(jour, plusHeures: -24),
                        basaleTime: Fixtures.instant(jour, plusHeures: -2),
                        doseLente: 18, glycemieCoucher: 95)
        ]
        var lectures = lecturesZone2([140, 135, 130])
        lectures += [(date: Fixtures.instant(jour, plusHeures: -1), valeur: 95, tendance: .stable)]

        let analyse = analyser(entrees(nuits: nuits, lectures: lectures))
        #expect(analyse.nuits.map(\.glycemieCoucher) == [95, 140])
    }
}
