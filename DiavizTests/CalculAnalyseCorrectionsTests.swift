//
//  CalculAnalyseCorrectionsTests.swift
//  DiavizTests
//
//  B3 — corrections du soir, event-based. La classification donne la
//  priorité à la sur-correction (l'événement dangereux), cherchée sur 6h,
//  avant l'insuffisance jugée sur 2h.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculAnalyseCorrectionsTests {

    private let jour = Fixtures.reference
    private var lente: Date { Fixtures.instant(jour, plusHeures: 22) }
    /// Correction prise 1h avant la lente — dans la zone 1 du coucher.
    private var heureCorrection: Date { Fixtures.instant(jour, plusHeures: 21) }

    // MARK: - Fabriques

    private func ancrage(doseLente: Double = 18) -> AncrageNuit {
        AncrageNuit(dateNuit: jour, basaleTime: lente, doseLente: doseLente, glycemieCoucher: 210)
    }

    /// Mesures après la correction, au pas indiqué.
    private func lectures(
        _ valeurs: [Int], depuis debut: Date? = nil, pasMinutes: Double = 15
    ) -> [(date: Date, valeur: Int, tendance: TendanceGlycemie?)] {
        let origine = debut ?? heureCorrection
        return valeurs.enumerated().map { index, valeur in
            (
                date: origine.addingTimeInterval(Double(index + 1) * pasMinutes * 60),
                valeur: valeur,
                tendance: .stable
            )
        }
    }

    private func entrees(
        nuits: [AncrageNuit]? = nil,
        lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)] = [],
        rapides: [(heure: Date, dose: Double, correction: Bool)]? = nil,
        repas: [(heure: Date, glucides: Int)] = [],
        sports: [(debut: Date, resume: SportResume)] = [],
        pauses: [(debut: Date, fin: Date?)] = []
    ) -> EntreesCorrections {
        EntreesCorrections(
            nuits: nuits ?? [ancrage()],
            lectures: lectures,
            rapides: rapides ?? [(heure: heureCorrection, dose: 3, correction: true)],
            repas: repas, sports: sports, pauses: pauses
        )
    }

    private func analyser(
        _ entrees: EntreesCorrections, changementDoseRecent: Date? = nil
    ) -> AnalyseCorrections {
        CalculAnalyseCorrections.analyser(entrees: entrees, changementDoseRecent: changementDoseRecent)
    }

    // MARK: - Population

    @Test("Aucune correction dans la fenêtre de coucher → aucun événement")
    func aucuneCorrection() {
        let analyse = analyser(entrees(lectures: lectures([200, 190, 170]), rapides: []))
        #expect(analyse.corrections.isEmpty)
    }

    @Test("Rapide non correctif → hors B3")
    func rapideNonCorrectif() {
        let analyse = analyser(entrees(
            lectures: lectures([200, 190, 170]),
            rapides: [(heure: heureCorrection, dose: 6, correction: false)]
        ))
        #expect(analyse.corrections.isEmpty)
    }

    @Test("Correction hors fenêtre de coucher (avant lente −3h) → ignorée")
    func correctionHorsFenetre() {
        let tot = Fixtures.instant(jour, plusHeures: 17)
        let analyse = analyser(entrees(
            lectures: lectures([200, 190, 170], depuis: tot),
            rapides: [(heure: tot, dose: 3, correction: true)]
        ))
        #expect(analyse.corrections.isEmpty)
    }

    @Test("Nuit sans lente → aucune fenêtre de coucher à examiner")
    func nuitSansLente() {
        let analyse = analyser(entrees(nuits: [ancrage(doseLente: 0)], lectures: lectures([200, 190, 170])))
        #expect(analyse.corrections.isEmpty)
    }

    @Test("Mode pause → correction non analysée")
    func modePause() {
        let pause = (debut: Fixtures.instant(jour, plusHeures: 12), fin: Optional(Fixtures.instant(jour, plusHeures: 30)))
        let analyse = analyser(entrees(lectures: lectures([200, 190, 170]), pauses: [pause]))
        #expect(analyse.corrections.isEmpty)
    }

    @Test("Nuit antérieure au changement de dose → hors fenêtre comparable")
    func fenetreDepuisChangementDeDose() {
        let analyse = analyser(
            entrees(lectures: lectures([200, 190, 170])),
            changementDoseRecent: Fixtures.instant(jour, plusHeures: 48)
        )
        #expect(analyse.corrections.isEmpty)
    }

    @Test("Aucune mesure après la correction → pas encore classable")
    func pasAssezDeRecul() {
        #expect(analyser(entrees(lectures: [])).corrections.isEmpty)
    }

    // MARK: - Classification

    @Test("Hypo dans les 6h → sur-correction, prioritaire")
    func surCorrection() {
        // Retour en cible sur les 2 premières heures, puis hypo à ~4h.
        var valeurs = Array(repeating: 150, count: 8)     // 15 min → 2h
        valeurs += Array(repeating: 120, count: 8)        // → 4h
        valeurs.append(60)
        let analyse = analyser(entrees(lectures: lectures(valeurs)))
        #expect(analyse.corrections.first?.issue == .surCorrection)
    }

    @Test("Reste au-dessus de la cible haute pendant 2h → insuffisante")
    func correctionInsuffisante() {
        let valeurs = Array(repeating: 220, count: 8)     // 15 min → 2h
        let analyse = analyser(entrees(lectures: lectures(valeurs)))
        #expect(analyse.corrections.first?.issue == .insuffisant)
    }

    @Test("Une seule mesure repassée en cible dans les 2h → adaptée")
    func correctionAdaptee() {
        var valeurs = Array(repeating: 220, count: 7)
        valeurs.append(160)
        let analyse = analyser(entrees(lectures: lectures(valeurs)))
        #expect(analyse.corrections.first?.issue == .adapte)
    }

    @Test("Mesure exactement à la cible haute → pas une insuffisance")
    func borneDeLaCibleHaute() {
        let analyse = analyser(entrees(lectures: lectures(Array(repeating: 180, count: 8))))
        #expect(analyse.corrections.first?.issue == .adapte)

        let auDessus = analyser(entrees(lectures: lectures(Array(repeating: 181, count: 8))))
        #expect(auDessus.corrections.first?.issue == .insuffisant)
    }

    @Test("Mesure exactement au seuil hypo → pas une sur-correction")
    func borneDuSeuilHypo() {
        var valeurs = Array(repeating: 150, count: 8)
        valeurs.append(70)
        #expect(analyser(entrees(lectures: lectures(valeurs))).corrections.first?.issue == .adapte)

        valeurs[valeurs.count - 1] = 69
        #expect(analyser(entrees(lectures: lectures(valeurs))).corrections.first?.issue == .surCorrection)
    }

    @Test("Mesures présentes seulement au-delà de 2h → pas classable")
    func mesuresTropTardives() {
        let tardives = lectures(Array(repeating: 150, count: 4), pasMinutes: 60)   // 1h → 4h
        let seulementApresDeuxHeures = tardives.filter {
            $0.date > heureCorrection.addingTimeInterval(2 * 3600)
        }
        #expect(analyser(entrees(lectures: seulementApresDeuxHeures)).corrections.isEmpty)
    }

    // MARK: - Contexte reporté

    @Test("Contexte de la correction : dose, glycémie, glucides, IOB")
    func contexteDeLaCorrection() {
        let repas = [(heure: heureCorrection.addingTimeInterval(-15 * 60), glucides: 20)]
        let rapides = [
            (heure: heureCorrection.addingTimeInterval(-3600), dose: 5.0, correction: false),
            (heure: heureCorrection, dose: 3.0, correction: true)
        ]
        var valeurs = Array(repeating: 150, count: 8)
        valeurs.insert(215, at: 0)

        let analyse = analyser(entrees(lectures: lectures(valeurs), rapides: rapides, repas: repas))
        let correction = analyse.corrections.first

        #expect(correction?.dose == 3)
        #expect(correction?.glycemie == 215)      // mesure la plus proche de la correction
        #expect(correction?.glucides == 20)
        #expect((correction?.iob ?? 0) > 0.05)    // la rapide d'il y a 1h compte encore
    }

    @Test("Corrections triées par glycémie croissante")
    func triParGlycemie() {
        let seconde = Fixtures.instant(jour, plusHeures: 21.5)
        let rapides = [
            (heure: heureCorrection, dose: 3.0, correction: true),
            (heure: seconde, dose: 2.0, correction: true)
        ]
        var mesures = lectures([230] + Array(repeating: 150, count: 8))
        mesures += lectures([190] + Array(repeating: 140, count: 8), depuis: seconde)

        let glycemies = analyser(entrees(lectures: mesures, rapides: rapides)).corrections.map(\.glycemie)
        #expect(glycemies == glycemies.sorted())
    }
}
