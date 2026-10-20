//
//  CalculEligibiliteRepasTests.swift
//  DiavizTests
//
//  Règle commune « ce repas peut-il juger un ratio, et lequel ? » —
//  partagée par l'analyse des ratios (R1) et les épisodes de charge (C1).
//

import Foundation
import Testing
@testable import Diaviz

struct CalculEligibiliteRepasTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func h(_ heures: Double) -> Date { t0.addingTimeInterval(heures * 3600) }

    private func repas(
        _ heure: Double, exclu: Bool = false, contexte: Bool = false, ajuste: Bool = false, id: UUID = UUID()
    ) -> RepasAJuger {
        RepasAJuger(id: id, heure: h(heure), doseCorrection: nil, exclureDesAnalyses: exclu, aUnEvenement: contexte, ajuste: ajuste)
    }

    private func evaluer(
        _ r: RepasAJuger, faits: FaitsFenetreRepas = FaitsFenetreRepas(),
        sport: [SeanceRatioSport] = [], ignorees: Set<RaisonExclusionFenetre> = []
    ) -> EligibiliteRepas {
        CalculEligibiliteRepas.evaluer(r, faits: faits, seancesRatioSport: sport, fenetreEffetSport: 3 * 3600, raisonsIgnorees: ignorees)
    }

    @Test func repasSeulJugeLeRatioDuMoment() {
        let e = evaluer(repas(12))
        #expect(e.estEligible)
        #expect(e.ratio == .moment)
    }

    @Test func uneSeuleRaisonDeBaseDansLOrdre() {
        #expect(evaluer(repas(12, exclu: true, ajuste: true)).raisons == [.exclusManuellement])
        #expect(evaluer(repas(12, contexte: true, ajuste: true)).raisons == [.contexteLibre])
        #expect(evaluer(repas(12, ajuste: true)).raisons == [.ajuste])
    }

    @Test func autreRepasDansLaFenetreEcarte() {
        let r = repas(12)
        var faits = FaitsFenetreRepas()
        faits.repas = [.init(id: r.id, heure: r.heure), .init(id: UUID(), heure: h(14))]
        #expect(evaluer(r, faits: faits).raisons == [.fenetre(.autreRepas)])
    }

    @Test func ratioSportEnVigueurApresLaSeance() {
        let seance = SeanceRatioSport(debut: h(10), fin: h(11), type: TypeSport.course.rawValue)
        let e = evaluer(repas(12), sport: [seance])
        #expect(e.ratio == .sport(type: TypeSport.course.rawValue))
    }

    @Test func laSeanceDuRatioSportNEstPasUnePollution() {
        let seance = SeanceRatioSport(debut: h(10), fin: h(11.5), type: TypeSport.course.rawValue)
        var faits = FaitsFenetreRepas()
        faits.seances = [.init(debut: seance.debut, fin: seance.fin)]
        #expect(evaluer(repas(12), faits: faits, sport: [seance]).estEligible)
    }

    @Test func uneAutreSeanceResteUnePollution() {
        let seance = SeanceRatioSport(debut: h(10), fin: h(11.5), type: TypeSport.course.rawValue)
        var faits = FaitsFenetreRepas()
        faits.seances = [.init(debut: seance.debut, fin: seance.fin), .init(debut: h(14), fin: h(15))]
        #expect(evaluer(repas(12), faits: faits, sport: [seance]).raisons == [.fenetre(.sport)])
    }

    @Test func seanceTropAncienneNeDeclenchePasLeRatioSport() {
        let seance = SeanceRatioSport(debut: h(6), fin: h(7), type: TypeSport.course.rawValue)
        #expect(evaluer(repas(12), sport: [seance]).ratio == .moment)
    }

    @Test func raisonsIgnoreesDuModeAvance() {
        let r = repas(12)
        var faits = FaitsFenetreRepas()
        faits.resucrages = [h(13)]
        #expect(!evaluer(r, faits: faits).estEligible)
        #expect(evaluer(r, faits: faits, ignorees: [.resucrage]).estEligible)
    }
}
