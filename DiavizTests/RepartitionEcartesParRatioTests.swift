//
//  RepartitionEcartesParRatioTests.swift
//  DiavizTests
//
//  Rangement des repas écartés par ratio appliqué — ce que la page
//  « Écart de ratio » affiche en touchant une gélule. Un mauvais arrondi ou
//  un repas compté deux fois ferait mentir la carte « Repas écartés ».
//

import Testing
@testable import Diaviz

struct RepartitionEcartesParRatioTests {

    @Test func rangeSousLeRatioArrondiCommeLesGelules() {
        var r = RepartitionRepasMoment()
        r.noterEcarte(glucides: 56, dose: 6, raisons: ["correction"])   // 9,33 → 9
        r.noterEcarte(glucides: 57, dose: 6, raisons: ["ajusté"])       // 9,5 → 10
        #expect(r.repasEcartesParRatio == [9: 1, 10: 1])
        #expect(r.ecartesParRatio[9] == ["correction": 1])
        #expect(r.ecartesParRatio[10] == ["ajusté": 1])
    }

    @Test func unRepasADeuxRaisonsCompteUneFoisCommeRepas() {
        var r = RepartitionRepasMoment()
        r.noterEcarte(glucides: 90, dose: 10, raisons: ["autre repas dans les 4 h", "correction"])
        r.noterEcarte(glucides: 90, dose: 10, raisons: ["correction"])
        #expect(r.repasEcartesParRatio[9] == 2)
        #expect(r.ecartesParRatio[9] == ["autre repas dans les 4 h": 1, "correction": 2])
    }

    @Test func sansDoseNiGlucidesRienNEstRange() {
        var r = RepartitionRepasMoment()
        r.noterEcarte(glucides: 0, dose: 5, raisons: ["ajusté"])
        r.noterEcarte(glucides: 50, dose: 0, raisons: ["ajusté"])
        r.noterEcarte(glucides: 50, dose: 5, raisons: [])
        #expect(r.repasEcartesParRatio.isEmpty)
        #expect(r.ecartesParRatio.isEmpty)
    }
}
