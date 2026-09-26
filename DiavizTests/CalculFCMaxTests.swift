//
//  CalculFCMaxTests.swift
//  DiavizTests
//
//  FC max personnelle — pic soutenu par séance (médiane glissante 60 s),
//  robustesse aux artefacts, repli sur la valeur théorique.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculFCMaxTests {

    /// Un échantillon toutes les `pas` secondes depuis `Fixtures.reference`.
    private func serie(_ bpm: [Double], pas: TimeInterval = 5) -> [EchantillonFC] {
        bpm.enumerated().map { EchantillonFC(date: Fixtures.reference.addingTimeInterval(Double($0.offset) * pas), bpm: $0.element) }
    }

    // MARK: - Pic soutenu

    @Test("Pic tenu plusieurs échantillons → retenu")
    func picTenu() {
        let bpm = Array(repeating: 140.0, count: 60) + Array(repeating: 182.0, count: 12) + Array(repeating: 150.0, count: 30)
        #expect(CalculFCMax.picSoutenu(serie(bpm)) == 182)
    }

    @Test("Artefact isolé à 230 → ignoré, le pic reste celui de l'effort réel")
    func artefactIsole() {
        var bpm = Array(repeating: 150.0, count: 60) + Array(repeating: 172.0, count: 12) + Array(repeating: 150.0, count: 30)
        bpm[30] = 230
        #expect(CalculFCMax.picSoutenu(serie(bpm)) == 172)
    }

    @Test("Deux artefacts voisins dans une fenêtre de 13 échantillons → toujours écartés")
    func deuxArtefacts() {
        var bpm = Array(repeating: 150.0, count: 60)
        bpm[20] = 230
        bpm[22] = 228
        #expect(CalculFCMax.picSoutenu(serie(bpm)) == 150)
    }

    @Test("Échantillonnage épars (un toutes les 5 min) → pas de pic mesurable")
    func echantillonnageEpars() {
        #expect(CalculFCMax.picSoutenu(serie([120, 160, 175, 150], pas: 300)) == nil)
        #expect(CalculFCMax.picSoutenu([]) == nil)
    }

    @Test("Échantillon hors plage (0, 300) → écarté avant calcul")
    func horsPlage() {
        let bpm: [Double] = [0, 300, 300, 300, 160, 161, 162]
        #expect(CalculFCMax.picSoutenu(serie(bpm)) == 161)
    }

    // MARK: - Retenue

    @Test("Moins de 10 séances avec pic → repli sur 190, théorique, nombre de séances gardé")
    func repliTheorique() {
        let retenue = CalculFCMax.retenir(pics: Array(repeating: 176.0, count: 9) + [nil, nil])
        #expect(retenue == FCMaxRetenue(bpm: 190, origine: .theorique, seancesAvecFC: 9))
        #expect(CalculFCMax.retenir(pics: []) == .theorique)
    }

    @Test("10 séances avec pic → la plus haute, observée")
    func observee() {
        let pics: [Double?] = [150, 162, 171, 158, 183, 166, 149, 177, 160, 155, nil]
        #expect(CalculFCMax.retenir(pics: pics) == FCMaxRetenue(bpm: 183, origine: .observee, seancesAvecFC: 10))
    }

    @Test("Pic soutenu invraisemblable (> 220) → séance écartée, ne fausse pas la valeur ni le compte")
    func picInvraisemblable() {
        let pics: [Double?] = Array(repeating: 170.0, count: 10) + [228]
        #expect(CalculFCMax.retenir(pics: pics) == FCMaxRetenue(bpm: 170, origine: .observee, seancesAvecFC: 10))
        let juste: [Double?] = Array(repeating: 170.0, count: 9) + [228]
        #expect(CalculFCMax.retenir(pics: juste).origine == .theorique)
    }

    // MARK: - Import

    @Test("Pré-remplissage à l'import : même FC max que la charge")
    func intensiteImport() {
        let observee = FCMaxRetenue(bpm: 170, origine: .observee, seancesAvecFC: 12)
        #expect(intensiteDepuisFC(140, fcMax: .theorique) == .moderee)   // 74 % de 190
        #expect(intensiteDepuisFC(140, fcMax: observee) == .intense)      // 82 % de 170
        #expect(intensiteDepuisFC(nil, fcMax: observee) == .moderee)
    }
}
