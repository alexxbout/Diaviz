//
//  CalculVerrouRatioTests.swift
//  DiavizTests
//
//  Délai entre deux changements de ratio : 5 repas enregistrés ou 14 jours,
//  au premier atteint. Un ratio jamais modifié n'est jamais verrouillé.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculVerrouRatioTests {

    private let calendrier = Calendar(identifier: .gregorian)

    private func jour(_ decalage: Int) -> Date {
        let origine = calendrier.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
        return calendrier.date(byAdding: .day, value: decalage, to: origine)!
    }

    private func etat(repas: Int, apres jours: Int) -> CalculVerrouRatio.Etat {
        CalculVerrouRatio.etat(
            dateChangement: jour(0), repasDepuis: repas,
            maintenant: jour(jours), calendrier: calendrier
        )
    }

    @Test("Jamais modifié → libre")
    func jamaisModifie() {
        let resultat = CalculVerrouRatio.etat(
            dateChangement: nil, repasDepuis: 0, maintenant: jour(0), calendrier: calendrier
        )
        #expect(resultat == .libre)
    }

    @Test("3 repas après 5 jours → verrouillé, 2 repas restants, date à J+14")
    func verrouille() {
        let attendu = calendrier.startOfDay(for: jour(14))
        #expect(etat(repas: 3, apres: 5) == .verrouille(repasRestants: 2, deblocage: attendu))
    }

    @Test("5 repas → libre, même le jour du changement")
    func seuilRepas() {
        #expect(etat(repas: 5, apres: 0) == .libre)
    }

    @Test("Le 14e jour → libre, même sans repas")
    func seuilJours() {
        #expect(etat(repas: 0, apres: 14) == .libre)
    }

    @Test("La veille du 14e jour → encore verrouillé")
    func veilleDuSeuil() {
        #expect(etat(repas: 4, apres: 13) != .libre)
    }
}
