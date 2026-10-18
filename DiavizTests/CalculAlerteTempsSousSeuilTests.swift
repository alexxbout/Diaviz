//
//  CalculAlerteTempsSousSeuilTests.swift
//  DiavizTests
//
//  Alerte « temps sous 70 mg/dL » : moyenne des 3 derniers jours terminés
//  strictement au-dessus de 3 %. Un jour sans donnée n'est jamais compté à
//  0 %, et trop peu de jours exploitables ne déclenche rien.
//

import Testing
@testable import Diaviz

struct CalculAlerteTempsSousSeuilTests {

    @Test("Moyenne au-dessus de 3 % → alerte avec la moyenne des trois jours")
    func moyenneAuDessus() {
        let resultat = CalculAlerteTempsSousSeuil.evaluer(parJour: [5.1, 1.8, 5.7])
        #expect(resultat != nil)
        #expect(abs((resultat?.moyenne ?? 0) - 4.2) < 0.001)
        #expect(resultat?.parJour == [5.1, 1.8, 5.7])
    }

    @Test("Moyenne sous 3 % même avec un jour très haut → pas d'alerte")
    func moyenneSousLeSeuil() {
        #expect(CalculAlerteTempsSousSeuil.evaluer(parJour: [7.0, 0.5, 0.5]) == nil)
    }

    @Test("Exactement 3 % → pas d'alerte (seuil dépassé strictement)")
    func pileSurLeSeuil() {
        #expect(CalculAlerteTempsSousSeuil.evaluer(parJour: [3.0, 3.0, 3.0]) == nil)
    }

    @Test("Jour sans donnée : exclu de la moyenne, pas compté à zéro")
    func jourManquantExclu() {
        // Compté à 0 %, la moyenne serait (4 + 4 + 0) / 3 = 2,7 % → pas d'alerte.
        let resultat = CalculAlerteTempsSousSeuil.evaluer(parJour: [4.0, nil, 4.0])
        #expect(resultat != nil)
        #expect(abs((resultat?.moyenne ?? 0) - 4.0) < 0.001)
    }

    @Test("Un seul jour exploitable → pas d'alerte, trop peu de recul")
    func unSeulJour() {
        #expect(CalculAlerteTempsSousSeuil.evaluer(parJour: [nil, nil, 9.0]) == nil)
    }

    @Test("Aucun jour exploitable → pas d'alerte")
    func aucunJour() {
        #expect(CalculAlerteTempsSousSeuil.evaluer(parJour: [nil, nil, nil]) == nil)
    }
}
