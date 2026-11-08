//
//  MarqueurFraicheurTests.swift
//  DiavizTests
//

import Foundation
import Testing
@testable import Diaviz

struct MarqueurFraicheurTests {

    private let depart = Date(timeIntervalSince1970: 1_000_000)

    private func marqueur(hub: Int = 1, charge: Int = 1, apres secondes: TimeInterval = 0) -> MarqueurFraicheur {
        MarqueurFraicheur(revisionHub: hub, revisionCharge: charge, instant: depart.addingTimeInterval(secondes))
    }

    @Test func resteValableSansChangement() {
        #expect(marqueur().resteValable(par: marqueur(apres: 60)))
    }

    @Test func expireQuandLeHubChange() {
        #expect(!marqueur().resteValable(par: marqueur(hub: 2, apres: 1)))
    }

    @Test func expireQuandLaChargeChange() {
        #expect(!marqueur().resteValable(par: marqueur(charge: 2, apres: 1)))
    }

    @Test func expireAvecLeTempsMemeSansDonnee() {
        let limite = MarqueurFraicheur.dureeValidite
        #expect(marqueur().resteValable(par: marqueur(apres: limite - 1)))
        #expect(!marqueur().resteValable(par: marqueur(apres: limite)))
    }

    @Test func expireSiHorlogeReculee() {
        #expect(!marqueur().resteValable(par: marqueur(apres: -1)))
    }

    private func charge(minutes: Double = 30, indice: Double? = 1, niveau: NiveauChargeActive? = .normale) -> ContexteChargeActive {
        ContexteChargeActive(
            contributions: [], debutHistorique: nil, marcheIncluse: true, fcMax: .theorique,
            jours: [JourChargeActive(
                jour: depart, nombreSeances: 1, minutesSeances: minutes, minutesMarche: 10,
                indice: indice, niveau: niveau, depuisJours: 1
            )],
            calendrier: .current
        )
    }

    @Test func indiceQuiGlisseNeChangePasLaCharge() {
        #expect(charge(indice: 1.0).memesFaits(que: charge(indice: 1.02)))
    }

    @Test func nouvelleDonneeChangeLaCharge() {
        #expect(!charge(minutes: 30).memesFaits(que: charge(minutes: 45)))
    }

    @Test func nouveauNiveauChangeLaCharge() {
        #expect(!charge(niveau: .normale).memesFaits(que: charge(niveau: .haute)))
    }
}
