//
//  CalculChargeActiviteTests.swift
//  DiavizTests
//
//  Charge d'activité sur 7 jours glissants — contexte transverse affiché sur
//  l'accueil et utilisé comme facteur « semaine intense » par B2/B3.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculChargeActiviteTests {

    private func seances(_ joursAvant: [Double]) -> [(debut: Date, dureeMin: Int)] {
        joursAvant.map { (debut: Fixtures.instant(plusHeures: -24 * $0), dureeMin: 60) }
    }

    @Test("Aucune séance → aucune charge")
    func aucuneSeance() {
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: []) == .aucune)
    }

    @Test("1 à 2 séances → semaine calme")
    func semaineCalme() {
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: seances([1])) == .calme)
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: seances([1, 3])) == .calme)
    }

    @Test("3 à 4 séances → semaine modérée")
    func semaineModeree() {
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: seances([1, 2, 3])) == .moderee)
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: seances([1, 2, 3, 4])) == .moderee)
    }

    @Test("5 séances et plus → semaine intense")
    func semaineIntense() {
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: seances([1, 2, 3, 4, 5])) == .intense)
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: seances([1, 2, 3, 4, 5, 6])) == .intense)
    }

    @Test("Séance exactement à la borne haute (l'instant évalué) : comptée")
    func borneHauteIncluse() {
        let activites = [(debut: Fixtures.reference, dureeMin: 45)]
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: activites) == .calme)
    }

    @Test("Séance exactement 7 jours avant : hors fenêtre")
    func borneBasseExclue() {
        let activites = [(debut: Fixtures.instant(plusHeures: -24 * 7), dureeMin: 45)]
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: activites) == .aucune)
    }

    @Test("Séance postérieure à l'instant évalué : hors fenêtre")
    func seancePosterieureIgnoree() {
        let activites = [(debut: Fixtures.instant(plusHeures: 1), dureeMin: 45)]
        #expect(CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: activites) == .aucune)
    }

    @Test("La durée des séances n'entre pas dans le calcul")
    func dureeSansEffet() {
        let courtes = [(debut: Fixtures.instant(plusHeures: -24), dureeMin: 5)]
        let longues = [(debut: Fixtures.instant(plusHeures: -24), dureeMin: 300)]
        #expect(
            CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: courtes)
                == CalculChargeActivite.charge(jusqua: Fixtures.reference, activites: longues)
        )
    }
}
