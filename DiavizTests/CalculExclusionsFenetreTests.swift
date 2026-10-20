//
//  CalculExclusionsFenetreTests.swift
//  DiavizTests
//
//  Un repas ne compte pour juger un ratio que si sa courbe ne mesure que
//  lui. Une règle trop lâche remet un point rouge trompeur dans R1.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculExclusionsFenetreTests {

    private let midi = Date(timeIntervalSince1970: 1_800_000_000)
    private let repasId = UUID()

    private func heure(_ minutes: Double) -> Date { midi.addingTimeInterval(minutes * 60) }

    private func raisons(
        doseCorrection: Double? = nil, _ modifier: (inout FaitsFenetreRepas) -> Void = { _ in }
    ) -> Set<RaisonExclusionFenetre> {
        var faits = FaitsFenetreRepas()
        faits.repas = [.init(id: repasId, heure: midi)]
        modifier(&faits)
        return CalculExclusionsFenetre.raisons(
            repasId: repasId, heure: midi, doseCorrection: doseCorrection, faits: faits
        )
    }

    private func injection(
        _ minutes: Double, dose: Double, correction: Bool = false, repas: UUID? = nil
    ) -> FaitsFenetreRepas.InjectionFait {
        .init(heure: heure(minutes), dose: dose, estRapide: true,
              estCorrection: correction, repasAssocieId: repas)
    }

    @Test func repasSeulPropre() {
        #expect(raisons { $0.injections = [injection(-10, dose: 6, repas: repasId)] }.isEmpty)
    }

    @Test func autreRepasDansLes4h() {
        #expect(raisons { $0.repas.append(.init(id: UUID(), heure: heure(120))) } == [.autreRepas])
    }

    @Test func autreRepasApres4hIgnore() {
        #expect(raisons { $0.repas.append(.init(id: UUID(), heure: heure(241))) }.isEmpty)
    }

    @Test func autreRepasDansLHeureAvant() {
        #expect(raisons { $0.repas.append(.init(id: UUID(), heure: heure(-30))) }.contains(.autreRepas))
    }

    @Test func insulineActiveDuRepasPrecedent() {
        // Bolus de 6 u il y a 2 h : bien au-dessus de 0,5 u restant.
        #expect(raisons { $0.injections = [injection(-120, dose: 6)] }.contains(.insulineActive))
    }

    @Test func insulineQuasiEpuiseeIgnoree() {
        // Bolus de 2 u il y a 3 h 50 (DIA 4 h) : reste < 0,5 u.
        #expect(!raisons { $0.injections = [injection(-230, dose: 2)] }.contains(.insulineActive))
    }

    @Test func preBolusDuRepasNeComptePas() {
        #expect(!raisons { $0.injections = [injection(-20, dose: 8, repas: repasId)] }.contains(.insulineActive))
    }

    @Test func correctionAvecLeRepas() {
        #expect(raisons(doseCorrection: 1) == [.correction])
    }

    @Test func correctionSepareeDansLaFenetre() {
        #expect(raisons { $0.injections = [injection(150, dose: 2, correction: true)] }.contains(.correction))
    }

    @Test func resucrageDansLaFenetre() {
        #expect(raisons { $0.resucrages = [heure(180)] } == [.resucrage])
    }

    @Test func sportQuiChevaucheLaFenetre() {
        #expect(raisons { $0.seances = [.init(debut: heure(200), fin: heure(260))] } == [.sport])
        #expect(raisons { $0.seances = [.init(debut: heure(-120), fin: heure(-61))] }.isEmpty)
    }

    @Test func toutesLesRaisonsConnues() {
        let r = raisons(doseCorrection: 1) {
            $0.repas.append(.init(id: UUID(), heure: heure(120)))
            $0.injections = [injection(-90, dose: 5)]
            $0.resucrages = [heure(200)]
            $0.seances = [.init(debut: heure(60), fin: heure(90))]
        }
        #expect(r == Set(RaisonExclusionFenetre.allCases))
    }
}
