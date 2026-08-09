//
//  CalculDetailSoireeTests.swift
//  DiavizTests
//
//  Sheet « Détail d'une soirée » : reconstruction de la chronologie et
//  passerelle vers le constat B1 de la même nuit. Dégradation gracieuse
//  attendue quand la nuit B1 manque.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculDetailSoireeTests {

    private let jour = Fixtures.reference
    /// Lente à J+22h — ancre de la nuit, comme dans B1.
    private var lente: Date { Fixtures.instant(jour, plusHeures: 22) }

    // MARK: - Fabriques

    private func soir(enHypo: Bool = true) -> SoirCoucher {
        SoirCoucher(
            id: UUID(), date: jour, glycemie: 105, tendance: .baisse,
            correction: nil, glucides: nil, sport: nil, iob: nil, charge: .aucune,
            categorieB1: nil, enHypo: enHypo, delaiHypoMinutes: enHypo ? 120 : nil,
            issueCorrection: nil
        )
    }

    /// Courbe 21h → 07h au pas de 5 min, plate à 110.
    private func courbe() -> [GlucosePoint] {
        (0..<121).map { index in
            GlucosePoint(
                time: Fixtures.instant(jour, plusHeures: 21).addingTimeInterval(Double(index) * 300),
                value: 110
            )
        }
    }

    private func zoneNuitProfonde() -> ZoneData {
        ZoneData(
            zone: .nuitProfonde,
            timeRange: lente.addingTimeInterval(2 * 3600)...lente.addingTimeInterval(5.5 * 3600),
            slope: -12,
            characteristic: .gradualDrop,
            isAnalyzed: true,
            exclusionReason: nil,
            events: []
        )
    }

    private func nuitB1(
        doseLente: Double = 18,
        slopeZone3: Double? = -12,
        zones: [ZoneData]? = nil,
        events: [NightEvent] = [],
        wakeUpGlucose: Double = 118,
        motifExclusion: String? = nil
    ) -> NightChartData {
        NightChartData(
            date: jour,
            glucoseValues: courbe(),
            basaleTime: lente,
            basaleDose: doseLente,
            startGlucose: 105,
            wakeUpGlucose: wakeUpGlucose,
            zones: zones ?? [zoneNuitProfonde()],
            events: events,
            overallStatus: .valid,
            slopeZone3: slopeZone3,
            motifExclusion: motifExclusion
        )
    }

    private func evenementHypo(minutesApresLente: Double, valeur: Double = 62) -> NightEvent {
        NightEvent(
            type: .hypo,
            time: lente.addingTimeInterval(minutesApresLente * 60),
            value: valeur,
            detail: "\(Int(valeur)) mg/dL"
        )
    }

    private func genres(_ detail: DetailSoiree) -> [String] {
        detail.evenements.map { evenement in
            switch evenement.genre {
            case .repas(_, let resucrage): resucrage ? "resucrage" : "repas"
            case .correction:              "correction"
            case .lente:                   "lente"
            case .hypo:                    "hypo"
            case .reveil:                  "reveil"
            }
        }
    }

    private func analyser(
        nuitB1 nuit: NightChartData?,
        rapides: [(heure: Date, dose: Double, correction: Bool)] = [],
        repas: [(heure: Date, glucides: Int)] = [],
        changementDoseRecent: Date? = nil
    ) -> DetailSoiree {
        CalculDetailSoiree.analyser(
            soir: soir(), nuitB1: nuit, rapides: rapides, repas: repas,
            changementDoseRecent: changementDoseRecent
        )
    }

    // MARK: - Dégradation gracieuse

    @Test("Sans nuit B1 : le soir seul, aucune chronologie inventée")
    func sansNuitB1() {
        let detail = analyser(nuitB1: nil, repas: [(heure: lente, glucides: 40)])

        #expect(detail.evenements.isEmpty)
        #expect(detail.courbe.isEmpty)
        #expect(detail.courbeIOB.isEmpty)
        #expect(detail.iobAuMomentHypo == nil)
        guard case .indisponible = detail.constatB1 else {
            Issue.record("attendu un constat B1 indisponible")
            return
        }
    }

    // MARK: - Chronologie

    @Test("Chronologie ordonnée : repas → correction → lente → hypo → réveil")
    func chronologieOrdonnee() {
        let detail = analyser(
            nuitB1: nuitB1(events: [evenementHypo(minutesApresLente: 150)]),
            rapides: [(heure: lente.addingTimeInterval(-30 * 60), dose: 2, correction: true)],
            repas: [(heure: lente.addingTimeInterval(-90 * 60), glucides: 60)]
        )

        #expect(genres(detail) == ["repas", "correction", "lente", "hypo", "reveil"])
        #expect(detail.evenements.map(\.heure) == detail.evenements.map(\.heure).sorted())
    }

    @Test("Repas pris juste après une hypo → affiché comme resucrage")
    func repasApresHypoEstUnResucrage() {
        let hypo = evenementHypo(minutesApresLente: 150)

        let colle = analyser(
            nuitB1: nuitB1(events: [hypo]),
            repas: [(heure: lente.addingTimeInterval(170 * 60), glucides: 15)]
        )
        #expect(genres(colle).contains("resucrage"))

        // Au-delà de 45 min après l'hypo, c'est un repas ordinaire.
        let plusTard = analyser(
            nuitB1: nuitB1(events: [hypo]),
            repas: [(heure: lente.addingTimeInterval(200 * 60), glucides: 15)]
        )
        #expect(genres(plusTard).contains("repas"))
        #expect(genres(plusTard).contains("resucrage") == false)
    }

    @Test("Seules les corrections de la fenêtre de coucher sont reprises")
    func correctionsFiltrees() {
        let rapides = [
            (heure: lente.addingTimeInterval(-30 * 60), dose: 2.0, correction: true),   // dans la fenêtre
            (heure: lente.addingTimeInterval(4 * 3600), dose: 1.0, correction: true),   // hors fenêtre
            (heure: lente.addingTimeInterval(-60 * 60), dose: 6.0, correction: false)   // bolus repas
        ]
        let detail = analyser(nuitB1: nuitB1(), rapides: rapides)
        #expect(genres(detail).filter { $0 == "correction" }.count == 1)
    }

    @Test("Lente absente de la chronologie quand aucune dose n'est enregistrée")
    func lenteAbsenteSansDose() {
        let detail = analyser(nuitB1: nuitB1(doseLente: 0))
        #expect(genres(detail).contains("lente") == false)
    }

    @Test("Réveil absent quand la glycémie de fin de nuit est inconnue")
    func reveilAbsentSansValeur() {
        let detail = analyser(nuitB1: nuitB1(wakeUpGlucose: 0))
        #expect(genres(detail).contains("reveil") == false)
    }

    @Test("Délai de l'hypo compté depuis la lente ; hypo antérieure sans délai")
    func delaiDeLHypo() {
        let apres = analyser(nuitB1: nuitB1(events: [evenementHypo(minutesApresLente: 150)]))
        let delaiApres = apres.evenements.compactMap { evenement -> Int?? in
            if case .hypo(_, let delai) = evenement.genre { return delai }
            return nil
        }.first
        #expect(delaiApres == 150)

        let avant = analyser(nuitB1: nuitB1(events: [evenementHypo(minutesApresLente: -60)]))
        let delaiAvant = avant.evenements.compactMap { evenement -> Int?? in
            if case .hypo(_, let delai) = evenement.genre { return delai }
            return nil
        }.first
        #expect(delaiAvant == Int?.none)
    }

    // MARK: - Constat B1

    @Test("Nuit B1 analysée : dérive et catégorie reprises")
    func constatAnalyse() {
        // Pente −12 mg/dL/h sur une zone 3 de 3,5 h → dérive −42 mg/dL.
        let detail = analyser(nuitB1: nuitB1())
        guard case .analysee(let derive, let categorie) = detail.constatB1 else {
            Issue.record("attendu un constat B1 analysé")
            return
        }
        #expect(derive == -42)
        #expect(categorie == .tendanceBasse)
    }

    @Test("Nuit B1 exclue : le motif est repris tel quel")
    func constatExclu() {
        let detail = analyser(nuitB1: nuitB1(motifExclusion: RaisonExclusion.chaotique.rawValue))
        guard case .exclue(let motif) = detail.constatB1 else {
            Issue.record("attendu un constat B1 exclu")
            return
        }
        #expect(motif == RaisonExclusion.chaotique.rawValue)
    }

    @Test("Nuit B1 sans pente exploitable → constat indisponible")
    func constatIndisponible() {
        let detail = analyser(nuitB1: nuitB1(slopeZone3: nil))
        guard case .indisponible = detail.constatB1 else {
            Issue.record("attendu un constat B1 indisponible")
            return
        }
    }

    // MARK: - IOB

    @Test("Courbe d'IOB au pas de 15 min, sur les bornes de la courbe glycémie")
    func courbeIOB() {
        let detail = analyser(
            nuitB1: nuitB1(),
            rapides: [(heure: lente, dose: 6, correction: false)]
        )

        #expect(detail.courbeIOB.first?.date == detail.courbe.first?.time)
        #expect(detail.courbeIOB.count == 41)     // 10 h au pas de 15 min
        #expect(detail.courbeIOB.contains { $0.iob > 0.05 })
    }

    @Test("IOB au moment de l'hypo : renseigné s'il reste de l'insuline active")
    func iobAuMomentDeLHypo() {
        let hypo = [evenementHypo(minutesApresLente: 60)]

        let avecInsuline = analyser(
            nuitB1: nuitB1(events: hypo),
            rapides: [(heure: lente, dose: 6, correction: false)]
        )
        #expect((avecInsuline.iobAuMomentHypo ?? 0) > 0.05)

        let sansInsuline = analyser(nuitB1: nuitB1(events: hypo))
        #expect(sansInsuline.iobAuMomentHypo == nil)
    }

    @Test("Seuil hypo du profil reporté sur la sheet")
    func seuilHypoReporte() {
        #expect(analyser(nuitB1: nuitB1()).seuilHypo == 70)
    }
}
