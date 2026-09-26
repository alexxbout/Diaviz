//
//  CalculCorrelationChargeTIRTests.swift
//  DiavizTests
//
//  Page « Charge et glycémie » — tranches par niveau de charge active du
//  jour, semaines en indice relatif.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculCorrelationChargeTIRTests {

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }

    private func jour(_ n: Int, niveau: NiveauChargeActive?) -> JourChargeActive {
        JourChargeActive(
            jour: Fixtures.instant(plusHeures: Double(n) * 24), nombreSeances: 0,
            minutesSeances: 0, minutesMarche: 0, indice: nil, niveau: niveau, depuisJours: nil
        )
    }

    @Test("Le TIR est regroupé par niveau de charge active du jour, n en jours")
    func tranchesParJour() {
        let contexte = ContexteChargeActive(
            contributions: [], debutHistorique: nil, marcheIncluse: true, fcMax: .theorique,
            jours: [jour(60, niveau: .haute), jour(61, niveau: .haute), jour(62, niveau: .basse), jour(63, niveau: nil)],
            calendrier: utc
        )
        let glucoses: [(date: Date, valeur: Int)] = [
            (Fixtures.instant(plusHeures: 60 * 24 + 10), 120), (Fixtures.instant(plusHeures: 60 * 24 + 11), 200),
            (Fixtures.instant(plusHeures: 61 * 24 + 10), 100),
            (Fixtures.instant(plusHeures: 62 * 24 + 10), 250),
            (Fixtures.instant(plusHeures: 63 * 24 + 10), 110),
        ]
        let synthese = CalculCorrelationChargeTIR.analyser(
            charge: contexte, glucoses: glucoses,
            nuitsDerive: [(Fixtures.instant(plusHeures: 61 * 24 + 22), -12)],
            maintenant: Fixtures.instant(plusHeures: 64 * 24), calendrier: utc
        )
        let haute = synthese.tranches.first { $0.niveau == .haute }
        #expect(haute?.nombreJours == 2)
        #expect(haute?.tirMoyen == 75)          // (50 + 100) / 2
        let basse = synthese.tranches.first { $0.niveau == .basse }
        #expect(basse?.nombreJours == 1)
        #expect(basse?.tirMoyen == 0)
        #expect(synthese.tranches.first { $0.niveau == .normale }?.nombreJours == 0)
        #expect(synthese.tranchesDerive.first { $0.niveau == .haute }?.nombreNuits == 1)
    }

    @Test("Sans recul, les semaines n'ont pas d'indice de charge")
    func semainesSansRecul() {
        let synthese = CalculCorrelationChargeTIR.analyser(
            charge: .vide, glucoses: [], maintenant: Fixtures.instant(plusHeures: 64 * 24), calendrier: utc
        )
        #expect(synthese.semaines.count == CalculCorrelationChargeTIR.nombreSemaines)
        #expect(synthese.semaines.allSatisfy { $0.indiceCharge == nil })
    }
}
