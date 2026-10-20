//
//  CalculCorrelationChargeTIRTests.swift
//  DiavizTests
//
//  Page « Charge et glycémie » — chronologie des semaines en indice relatif.
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

    @Test("Sans recul, les semaines n'ont pas d'indice de charge")
    func semainesSansRecul() {
        let synthese = CalculCorrelationChargeTIR.analyser(
            charge: .vide, glucoses: [], maintenant: Fixtures.instant(plusHeures: 64 * 24), calendrier: utc
        )
        #expect(synthese.semaines.count == CalculCorrelationChargeTIR.nombreSemaines)
        #expect(synthese.semaines.allSatisfy { $0.indiceCharge == nil })
    }
}
