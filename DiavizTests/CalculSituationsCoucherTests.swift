//
//  CalculSituationsCoucherTests.swift
//  DiavizTests
//
//  B2/B3 — fusion des soirs et mining des situations. Critères de remontée
//  documentés : effectif ≥ 3, hypos ≥ 2, écart de taux ≥ 25 points vs
//  complément, flag « fragile » sous 4 soirs, une paire ne s'affiche que si
//  elle bat nettement ses facteurs seuls.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculSituationsCoucherTests {

    // MARK: - Fabriques

    private func soir(
        jour: Int,
        glycemie: Int = 110,
        sport: Bool = false,
        charge: ChargeActivite = .aucune,
        hypo: Bool = false,
        iob: Double? = nil,
        categorieB1: CategorieNuit? = nil,
        correction: Double? = nil
    ) -> SoirCoucher {
        let date = Fixtures.instant(plusHeures: Double(jour) * 24)
        return SoirCoucher(
            id: UUID(),
            date: date,
            dateNuit: Calendar.current.startOfDay(for: date),
            glycemie: glycemie,
            tendance: .stable,
            correction: correction,
            glucides: nil,
            sport: sport ? SportResume(type: "Course", intensite: "modéré", dureeMinutes: 45) : nil,
            iob: iob,
            charge: charge,
            categorieB1: categorieB1,
            enHypo: hypo,
            delaiHypoMinutes: hypo ? 90 : nil,
            issueCorrection: correction != nil ? (hypo ? .surCorrection : .adapte) : nil
        )
    }

    /// Situation portant sur un facteur donné, ou `nil` si elle n'a pas été
    /// retenue par le mining.
    private func situation(
        _ situations: [SituationCoucher], facteurs: [FacteurCoucher]
    ) -> SituationCoucher? {
        situations.first { $0.facteurs == facteurs }
    }

    // MARK: - Tranches de glycémie

    @Test("Bornes exactes des tranches de coucher")
    func bornesDesTranches() {
        #expect(TrancheCoucher.pour(glycemie: 99) == .moins100)
        #expect(TrancheCoucher.pour(glycemie: 100) == .de100a130)
        #expect(TrancheCoucher.pour(glycemie: 129) == .de100a130)
        #expect(TrancheCoucher.pour(glycemie: 130) == .de130a160)
        #expect(TrancheCoucher.pour(glycemie: 159) == .de130a160)
        #expect(TrancheCoucher.pour(glycemie: 160) == .hautCorrige)
    }

    @Test("Présence des facteurs sur un soir")
    func presenceDesFacteurs() {
        let complet = soir(jour: 0, glycemie: 95, sport: true, charge: .intense,
                           iob: 1.2, categorieB1: .tendanceBasse, correction: 2)
        #expect(FacteurCoucher.tranche(.moins100).present(dans: complet))
        #expect(FacteurCoucher.sportJour.present(dans: complet))
        #expect(FacteurCoucher.insulineActive.present(dans: complet))
        #expect(FacteurCoucher.chargeIntense.present(dans: complet))
        #expect(FacteurCoucher.nuitDescendante.present(dans: complet))
        #expect(FacteurCoucher.correctionPrise.present(dans: complet))

        let nu = soir(jour: 1, glycemie: 140, charge: .calme, categorieB1: .stable)
        #expect(FacteurCoucher.sportJour.present(dans: nu) == false)
        #expect(FacteurCoucher.insulineActive.present(dans: nu) == false)
        #expect(FacteurCoucher.chargeIntense.present(dans: nu) == false)
        #expect(FacteurCoucher.nuitDescendante.present(dans: nu) == false)
        #expect(FacteurCoucher.correctionPrise.present(dans: nu) == false)
    }

    // MARK: - Seuils de remontée

    @Test("Aucun soir → aucune situation")
    func aucunSoir() {
        #expect(CalculSituationsCoucher.minerSituations([]).isEmpty)
    }

    @Test("Effectif exactement à 3 avec 2 hypos → situation remontée")
    func effectifAuSeuilExact() {
        let soirs = [
            soir(jour: 0, sport: true, hypo: true),
            soir(jour: 1, sport: true, hypo: true),
            soir(jour: 2, sport: true),
            soir(jour: 3),
            soir(jour: 4),
            soir(jour: 5)
        ]
        let sportSeul = situation(CalculSituationsCoucher.minerSituations(soirs), facteurs: [.sportJour])

        #expect(sportSeul != nil)
        #expect(sportSeul?.total == 3)
        #expect(sportSeul?.hypos == 2)
        #expect(sportSeul?.complementTotal == 3)
        #expect(sportSeul?.complementHypos == 0)
    }

    @Test("Effectif à 2 → sous le seuil, rien remonté")
    func effectifSousLeSeuil() {
        let soirs = [
            soir(jour: 0, sport: true, hypo: true),
            soir(jour: 1, sport: true, hypo: true),
            soir(jour: 2),
            soir(jour: 3),
            soir(jour: 4)
        ]
        #expect(situation(CalculSituationsCoucher.minerSituations(soirs), facteurs: [.sportJour]) == nil)
    }

    @Test("Une seule hypo dans la situation → pas d'anecdote remontée")
    func uneSeuleHypo() {
        let soirs = [
            soir(jour: 0, sport: true, hypo: true),
            soir(jour: 1, sport: true),
            soir(jour: 2, sport: true),
            soir(jour: 3),
            soir(jour: 4),
            soir(jour: 5)
        ]
        #expect(situation(CalculSituationsCoucher.minerSituations(soirs), facteurs: [.sportJour]) == nil)
    }

    @Test("Écart exactement à 25 points → retenu")
    func ecartAuSeuilExact() {
        // Situation 2/4 = 0,50 · complément 1/4 = 0,25 → 25 points pile.
        let soirs = [
            soir(jour: 0, sport: true, hypo: true),
            soir(jour: 1, sport: true, hypo: true),
            soir(jour: 2, sport: true),
            soir(jour: 3, sport: true),
            soir(jour: 4, hypo: true),
            soir(jour: 5), soir(jour: 6), soir(jour: 7)
        ]
        let sportSeul = situation(CalculSituationsCoucher.minerSituations(soirs), facteurs: [.sportJour])
        #expect(sportSeul != nil)
        #expect(sportSeul?.ecart == 0.25)
    }

    @Test("Écart juste sous 25 points → écarté")
    func ecartJusteSousLeSeuil() {
        // Situation 2/4 = 0,50 · complément 13/50 = 0,26 → 24 points.
        var soirs = [
            soir(jour: 0, sport: true, hypo: true),
            soir(jour: 1, sport: true, hypo: true),
            soir(jour: 2, sport: true),
            soir(jour: 3, sport: true)
        ]
        soirs += (0..<50).map { index in soir(jour: 10 + index, hypo: index < 13) }
        #expect(situation(CalculSituationsCoucher.minerSituations(soirs), facteurs: [.sportJour]) == nil)
    }

    @Test("Complément vide → aucune situation (rien à contraster)")
    func complementVide() {
        let soirs = (0..<5).map { soir(jour: $0, sport: true, hypo: $0 < 3) }
        #expect(situation(CalculSituationsCoucher.minerSituations(soirs), facteurs: [.sportJour]) == nil)
    }

    @Test("Flag « fragile » sous 4 soirs")
    func flagFragile() {
        let troisSoirs = [
            soir(jour: 0, sport: true, hypo: true),
            soir(jour: 1, sport: true, hypo: true),
            soir(jour: 2, sport: true),
            soir(jour: 3), soir(jour: 4), soir(jour: 5)
        ]
        #expect(situation(CalculSituationsCoucher.minerSituations(troisSoirs), facteurs: [.sportJour])?.fragile == true)

        let quatreSoirs = troisSoirs + [soir(jour: 6, sport: true, hypo: true)]
        #expect(situation(CalculSituationsCoucher.minerSituations(quatreSoirs), facteurs: [.sportJour])?.fragile == false)
    }

    // MARK: - Paires de facteurs

    @Test("Deux facteurs de la même famille ne sont jamais croisés")
    func famillesNonCroisees() {
        let soirs = (0..<10).map { index in
            soir(jour: index, hypo: index < 5, iob: 1.5, correction: 3)
        } + (0..<6).map { index in soir(jour: 20 + index) }

        let paires = CalculSituationsCoucher.minerSituations(soirs).filter { !$0.estFacteurSeul }
        #expect(paires.allSatisfy { $0.facteurs[0].famille != $0.facteurs[1].famille })
        #expect(FacteurCoucher.insulineActive.famille == FacteurCoucher.correctionPrise.famille)
    }

    @Test("Une paire redondante avec son facteur seul est écartée")
    func paireRedondante() {
        // Le sport explique tout : la charge intense n'ajoute rien.
        let soirs = [
            soir(jour: 0, sport: true, charge: .intense, hypo: true),
            soir(jour: 1, sport: true, charge: .intense, hypo: true),
            soir(jour: 2, sport: true, charge: .intense, hypo: true),
            soir(jour: 3, sport: true, charge: .calme, hypo: true),
            soir(jour: 4, sport: true, charge: .calme, hypo: true),
            soir(jour: 5), soir(jour: 6), soir(jour: 7), soir(jour: 8)
        ]
        let situations = CalculSituationsCoucher.minerSituations(soirs)
        #expect(situation(situations, facteurs: [.sportJour]) != nil)
        #expect(situation(situations, facteurs: [.sportJour, .chargeIntense]) == nil)
    }

    @Test("Situations triées par écart décroissant")
    func triParEcart() {
        let soirs = [
            soir(jour: 0, glycemie: 95, sport: true, hypo: true),
            soir(jour: 1, glycemie: 95, sport: true, hypo: true),
            soir(jour: 2, glycemie: 95, sport: true, hypo: true),
            soir(jour: 3, glycemie: 140, hypo: true),
            soir(jour: 4, glycemie: 140, hypo: true),
            soir(jour: 5, glycemie: 140),
            soir(jour: 6, glycemie: 140),
            soir(jour: 7, glycemie: 140),
            soir(jour: 8, glycemie: 140)
        ]
        let ecarts = CalculSituationsCoucher.minerSituations(soirs).map(\.ecart)
        #expect(ecarts == ecarts.sorted(by: >))
    }

    // MARK: - Fusion B2 + B3

    @Test("Fusion : soirs B2 et B3 réunis, triés du plus récent au plus ancien")
    func fusionDesDeuxPopulations() {
        let jour = Fixtures.reference
        let b2 = AnalyseEndormissement(
            seuilCoucher: 160,
            doseActuelle: 18,
            nuits: [
                NuitEndormissement(
                    id: UUID(), date: jour, glycemieCoucher: 95, tendance: .baisse,
                    glucides: nil, sport: nil, iob: nil, charge: .aucune,
                    issue: .hypo(delaiMinutes: 80)
                )
            ]
        )
        let b3 = AnalyseCorrections(corrections: [
            CorrectionSoir(
                id: UUID(), date: jour.addingTimeInterval(24 * 3600), glycemie: 210,
                tendance: .hausse, glucides: nil, dose: 3, iob: nil, sport: nil,
                charge: .aucune, issue: .surCorrection
            )
        ])

        let analyse = CalculSituationsCoucher.analyser(endormissement: b2, corrections: b3, timeline: [])

        #expect(analyse.totalSoirs == 2)
        #expect(analyse.totalHypos == 2)
        #expect(analyse.doseActuelle == 18)
        #expect(analyse.seuilCoucher == 160)
        #expect(analyse.soirs.first?.glycemie == 210)          // le plus récent d'abord
        #expect(analyse.soirs.first?.correction == 3)
        #expect(analyse.soirs.last?.delaiHypoMinutes == 80)
    }

    @Test("Une correction « insuffisante » n'est pas une hypo")
    func correctionInsuffisanteHorsFocusHypo() {
        let b3 = AnalyseCorrections(corrections: [
            CorrectionSoir(
                id: UUID(), date: Fixtures.reference, glycemie: 240, tendance: .stable,
                glucides: nil, dose: 2, iob: nil, sport: nil, charge: .aucune, issue: .insuffisant
            )
        ])
        let analyse = CalculSituationsCoucher.analyser(
            endormissement: AnalyseEndormissement(seuilCoucher: 160, doseActuelle: 18, nuits: []),
            corrections: b3, timeline: []
        )

        #expect(analyse.totalSoirs == 1)
        #expect(analyse.totalHypos == 0)
        #expect(analyse.soirs.first?.issueCorrection == .insuffisant)
    }

    @Test("Catégorie B1 reprise de la timeline pour la nuit correspondante")
    func categorieB1DepuisTimeline() {
        let cal = Calendar.current
        let jour = Fixtures.reference
        let b2 = AnalyseEndormissement(
            seuilCoucher: 160, doseActuelle: 18,
            nuits: [
                NuitEndormissement(
                    id: UUID(), date: jour, glycemieCoucher: 95, tendance: .stable,
                    glucides: nil, sport: nil, iob: nil, charge: .aucune, issue: .stable
                )
            ]
        )
        let timeline = [
            NuitTimeline(date: cal.startOfDay(for: jour),
                         etat: .valide(categorie: .tendanceBasse), avantChangementDose: false)
        ]

        let avec = CalculSituationsCoucher.analyser(
            endormissement: b2, corrections: AnalyseCorrections(corrections: []), timeline: timeline
        )
        #expect(avec.soirs.first?.categorieB1 == .tendanceBasse)

        let sans = CalculSituationsCoucher.analyser(
            endormissement: b2, corrections: AnalyseCorrections(corrections: []), timeline: []
        )
        #expect(sans.soirs.first?.categorieB1 == nil)
    }

    @Test("Nuit B1 exclue → aucune catégorie reprise")
    func nuitB1Exclue() {
        let cal = Calendar.current
        let jour = Fixtures.reference
        let b2 = AnalyseEndormissement(
            seuilCoucher: 160, doseActuelle: 18,
            nuits: [
                NuitEndormissement(
                    id: UUID(), date: jour, glycemieCoucher: 95, tendance: .stable,
                    glucides: nil, sport: nil, iob: nil, charge: .aucune, issue: .stable
                )
            ]
        )
        let timeline = [
            NuitTimeline(date: cal.startOfDay(for: jour),
                         etat: .exclue(raison: .cgmIncomplet), avantChangementDose: false)
        ]
        let analyse = CalculSituationsCoucher.analyser(
            endormissement: b2, corrections: AnalyseCorrections(corrections: []), timeline: timeline
        )
        #expect(analyse.soirs.first?.categorieB1 == nil)
    }
}
