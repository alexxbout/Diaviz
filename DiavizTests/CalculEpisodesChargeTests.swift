//
//  CalculEpisodesChargeTests.swift
//  DiavizTests
//
//  Épisodes de charge et états des réglages (docs/analyses/C1 — Frise des
//  périodes.md) : découpage par niveau, comptes d'entrée et de sortie,
//  garde-fou hypo, nuits d'observation de la lente, valeur retenue,
//  comparaison par charge réelle.
//

import Foundation
import Testing
@testable import Diaviz

@MainActor
struct CalculEpisodesChargeTests {

    private typealias C = CalculEpisodesCharge

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }()
    private var j0: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? Date() }

    private func jour(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: j0) ?? j0 }

    private func nuits(_ issues: [IssueEvenement], valeur: Double = 16, depuis debut: Int = 0) -> [EvenementReglage] {
        issues.enumerated().map {
            EvenementReglage(date: jour(debut + $0.offset), reglage: .lente, valeur: valeur, issue: $0.element)
        }
    }

    private func marques(_ evenements: [EvenementReglage]) -> [C.EvenementMarque] {
        C.segmenter(evenements).flatMap(\.evenements)
    }

    // MARK: - Comptes et garde-fou

    @Test func pasAssezDeReculSousLeMinimum() {
        let (etat, _) = C.rejouer(marques(nuits([.concluant, .concluant, .concluant, .concluant])), regle: .lente)
        #expect(etat == .pasAssezDeRecul(evaluables: 4, requis: 5))
    }

    @Test func concluanteACinqNuitsSurSept() {
        let (etat, atteint) = C.rejouer(
            marques(nuits([.concluant, .rate, .concluant, .concluant, .rate, .concluant, .concluant])),
            regle: .lente
        )
        #expect(etat == .concluant(concluants: 5, fenetre: 7, hypos: 0))
        #expect(atteint)
    }

    @Test func uneHypoNEmpechePas() {
        let (etat, _) = C.rejouer(
            marques(nuits([.concluant, .hypo, .concluant, .concluant, .rate, .concluant, .concluant])),
            regle: .lente
        )
        #expect(etat == .concluant(concluants: 5, fenetre: 7, hypos: 1))
    }

    @Test func deuxHyposBloquentQuelQueSoitLeCompte() {
        let (etat, atteint) = C.rejouer(
            marques(nuits([.concluant, .hypo, .concluant, .concluant, .hypo, .concluant, .concluant])),
            regle: .lente
        )
        #expect(etat == .ajustement(concluants: 5, fenetre: 7, hypos: 2))
        #expect(!atteint)
    }

    @Test func deuxiemeHypoFaitRepasserEnAjustement() {
        let issues: [IssueEvenement] = [.concluant, .concluant, .concluant, .concluant, .concluant, .hypo, .hypo]
        let (etat, atteint) = C.rejouer(marques(nuits(issues)), regle: .lente)
        #expect(atteint)
        #expect(etat == .ajustement(concluants: 5, fenetre: 7, hypos: 2))
    }

    @Test func hystereseResteConcluanteAuDessusDuSeuilDeSortie() {
        // 7 concluantes puis 3 ratées : fenêtre = 4 concluantes, au-dessus
        // de la sortie (3), l'état reste concluant.
        let issues: [IssueEvenement] = Array(repeating: .concluant, count: 7) + [.rate, .rate, .rate]
        let (etat, _) = C.rejouer(marques(nuits(issues)), regle: .lente)
        #expect(etat == .concluant(concluants: 4, fenetre: 7, hypos: 0))
    }

    @Test func nonEvaluablesNeComptentPas() {
        let issues: [IssueEvenement] = [.concluant, .nonEvaluable, .concluant, .nonEvaluable, .concluant, .concluant]
        let (etat, _) = C.rejouer(marques(nuits(issues)), regle: .lente)
        #expect(etat == .pasAssezDeRecul(evaluables: 4, requis: 5))
    }

    // MARK: - Transition de la lente

    @Test func deuxNuitsDObservationApresUnChangement() {
        let evenements = nuits([.concluant, .concluant], valeur: 17)
            + nuits([.rate, .rate, .concluant], valeur: 16, depuis: 2)
        let segments = C.segmenter(evenements)
        #expect(segments.count == 2)
        #expect(segments[0].evenements.allSatisfy { !$0.enObservation })
        #expect(segments[1].evenements.map(\.enObservation) == [true, true, false])
    }

    @Test func pasDeTransitionPourUnRatio() {
        let repas = [12.0, 12, 11, 11].enumerated().map {
            EvenementReglage(date: jour($0.offset), reglage: .ratio(.midi), valeur: $0.element, issue: .concluant)
        }
        #expect(C.segmenter(repas).flatMap(\.evenements).allSatisfy { !$0.enObservation })
    }

    @Test func etatObservationPendantLaTransition() {
        let segments = C.segmenter(nuits([.concluant, .concluant], valeur: 17) + nuits([.rate], valeur: 16, depuis: 2))
        let etat = C.etatActuel(reglage: .lente, segments: segments, valeurActuelle: 16, debutEpisode: jour(0))
        #expect(etat.etat == .observation(faites: 1, sur: 2))
        #expect(etat.changement?.ancienne == 17)
    }

    @Test func nouvelleDoseSansNuitEncore() {
        let segments = C.segmenter(nuits([.concluant, .concluant], valeur: 17))
        let etat = C.etatActuel(reglage: .lente, segments: segments, valeurActuelle: 16, debutEpisode: jour(0))
        #expect(etat.etat == .observation(faites: 0, sur: 2))
    }

    @Test func nouvelEpisodeRepartDeZero() {
        let segments = C.segmenter(nuits(Array(repeating: .concluant, count: 10)))
        let etat = C.etatActuel(reglage: .lente, segments: segments, valeurActuelle: 16, debutEpisode: jour(8))
        #expect(etat.etat == .pasAssezDeRecul(evaluables: 2, requis: 5))
        #expect(etat.evenements.count == 2)
    }

    // MARK: - Valeur retenue

    @Test func retientLaValeurAuPlusDeConcluants() {
        let evenements = nuits(Array(repeating: .concluant, count: 6), valeur: 16)
            + nuits(Array(repeating: .concluant, count: 10), valeur: 15, depuis: 6)
        let usages = C.usagesDansPlage(C.segmenter(evenements), debut: jour(0), fin: jour(20), regle: .lente)
        guard case .concluante(let retenue) = C.retenir(usages) else {
            Issue.record("valeur concluante attendue"); return
        }
        #expect(retenue.valeur == 15)
        #expect(retenue.concluants == 8) // 2 nuits d'observation après le changement
    }

    @Test func aucuneValeurConcluante() {
        let usages = C.usagesDansPlage(
            C.segmenter(nuits([.rate, .rate, .concluant, .rate, .rate, .rate])),
            debut: jour(0), fin: jour(10), regle: .lente
        )
        #expect(C.retenir(usages) == .aucune(derniere: 16))
    }

    @Test func tropCourtPartout() {
        let usages = C.usagesDansPlage(C.segmenter(nuits([.concluant, .concluant])), debut: jour(0), fin: jour(10), regle: .lente)
        #expect(C.retenir(usages) == .pasAssezDeRecul)
    }

    // MARK: - Historique des valeurs

    @Test func valeurReconstitueeDepuisLesChangements() {
        let midi = CleParametre(parametre: .ratioDejeuner)
        let changements = [
            (date: jour(10), cle: midi, ancienne: Optional(12.0)),
            (date: jour(20), cle: midi, ancienne: Optional(11.0)),
        ]
        let v = { (n: Int) in
            ChargeurEpisodesCharge.valeur(a: jour(n), cle: midi, courante: 10, changements: changements, inconnueAvant: nil)
        }
        #expect(v(5) == 12)
        #expect(v(15) == 11)
        #expect(v(25) == 10)
        #expect(ChargeurEpisodesCharge.valeur(
            a: jour(5), cle: midi, courante: 10, changements: changements, inconnueAvant: jour(8)
        ) == nil)
    }

    // MARK: - Épisodes

    private func jours(_ niveaux: [NiveauChargeActive?]) -> [JourChargeActive] {
        niveaux.enumerated().map {
            JourChargeActive(
                jour: jour($0.offset), nombreSeances: 1, minutesSeances: 45, minutesMarche: 10,
                indice: nil, niveau: $0.element, depuisJours: nil
            )
        }
    }

    @Test func decoupeParNiveau() {
        let plages = C.decouper(jours([nil, nil, .normale, .normale, .normale, .haute, .haute]))
        #expect(plages.map(\.niveau) == [nil, .normale, .haute])
        #expect(plages.map(\.jours.count) == [2, 3, 2])
    }

    @Test func comparablesParChargeReelle() {
        // Charge forte les 4 premiers jours (haute), faible au milieu
        // (référence), forte à nouveau en fin : le premier épisode est
        // comparable à celui en cours, le deuxième ne l'est pas.
        // Épisodes de 10 jours, amorce avant le premier pour partir du
        // régime établi.
        let niveaux: [NiveauChargeActive?] = Array(repeating: .haute, count: 10)
            + Array(repeating: .normale, count: 10) + Array(repeating: .haute, count: 10)
        let contributions = (-10..<30).filter { !(10..<20).contains($0) }.map { i in
            ContributionCharge(instant: jour(i).addingTimeInterval(18 * 3600), charge: 100)
        }
        let contexte = ContexteChargeActive(
            contributions: contributions, debutHistorique: jour(0), marcheIncluse: true,
            fcMax: .theorique, jours: jours(niveaux), calendrier: cal
        )
        let synthese = C.analyser(
            charge: contexte, evenements: [], valeursActuelles: [:],
            glycemies: [], resucrages: [], maintenant: jour(29).addingTimeInterval(20 * 3600)
        )
        #expect(synthese.enCours?.niveau == .haute)
        #expect(synthese.precedent?.niveau == .normale)
        #expect(synthese.comparables.map(\.debut) == [jour(0)])
        #expect(synthese.autres.map(\.debut) == [jour(10)])
    }
}
