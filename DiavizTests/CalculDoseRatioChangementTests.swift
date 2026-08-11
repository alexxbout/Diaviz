//
//  CalculDoseRatioChangementTests.swift
//  DiavizTests
//
//  Comparaison dose/verdict avant-après un changement de ratio. Seul
//  garde-fou : 5 repas après le changement. Un `<` de travers ici fait
//  apparaître (ou disparaître) le bloc « depuis le changement de ratio »
//  dans la sheet Écart de ratio.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculDoseRatioChangementTests {

    // MARK: - Fabriques

    private let changement = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// `nombre` repas à une dose donnée, dont `bons` avec un bon verdict,
    /// répartis `joursDecalage` jours avant/après `changement` (négatif =
    /// avant, positif = après).
    private func repas(nombre: Int, bons: Int, dose: Double, joursDecalage: Int) -> [EntreeDoseChangement] {
        (0..<nombre).map { index in
            EntreeDoseChangement(
                heure: changement.addingTimeInterval(Double(joursDecalage + index) * 86_400),
                doseAppliquee: dose,
                verdict: index < bons ? .bon : .mauvais
            )
        }
    }

    // MARK: - Garde-fou d'effectif

    @Test("Aucune entrée → pas de comparaison")
    func aucuneEntree() {
        #expect(CalculDoseRatioChangement.comparer(entrees: [], dateChangement: changement) == nil)
    }

    @Test("Exactement 5 repas après le changement → comparaison produite")
    func seuilExact() {
        let entrees = repas(nombre: 5, bons: 3, dose: 6, joursDecalage: 1)
        let comparaison = CalculDoseRatioChangement.comparer(entrees: entrees, dateChangement: changement)
        #expect(comparaison?.apres.effectif == 5)
    }

    @Test("4 repas après le changement → aucune comparaison")
    func sousLeSeuil() {
        let entrees = repas(nombre: 4, bons: 3, dose: 6, joursDecalage: 1)
        #expect(CalculDoseRatioChangement.comparer(entrees: entrees, dateChangement: changement) == nil)
    }

    @Test("Repas avant le changement ne comptent pas dans l'effectif « après »")
    func avantNeComptePasDansApres() {
        let entrees = repas(nombre: 10, bons: 5, dose: 7, joursDecalage: -20)
            + repas(nombre: 5, bons: 2, dose: 6, joursDecalage: 1)
        let comparaison = CalculDoseRatioChangement.comparer(entrees: entrees, dateChangement: changement)
        #expect(comparaison?.apres.effectif == 5)
    }

    // MARK: - Bornes temporelles

    @Test("Un repas exactement à la date de changement compte dans « après »")
    func borneInclusePourApres() {
        let entrees: [EntreeDoseChangement] = [
            EntreeDoseChangement(heure: changement, doseAppliquee: 5, verdict: .bon)
        ] + repas(nombre: 4, bons: 4, dose: 5, joursDecalage: 1)
        let comparaison = CalculDoseRatioChangement.comparer(entrees: entrees, dateChangement: changement)
        #expect(comparaison?.apres.effectif == 5)
    }

    // MARK: - Stats

    @Test("Dose moyenne et taux de bons verdicts calculés sur chaque période")
    func statsCalculees() {
        let avant = repas(nombre: 6, bons: 3, dose: 8, joursDecalage: -30)
        let apres = repas(nombre: 5, bons: 4, dose: 6, joursDecalage: 1)
        let comparaison = CalculDoseRatioChangement.comparer(entrees: avant + apres, dateChangement: changement)

        #expect(comparaison?.avant?.doseMoyenne == 8)
        #expect(comparaison?.avant?.tauxBon == 0.5)
        #expect(comparaison?.avant?.effectif == 6)
        #expect(comparaison?.apres.doseMoyenne == 6)
        #expect(comparaison?.apres.tauxBon == 0.8)
        #expect(comparaison?.apres.effectif == 5)
    }

    @Test("Aucun repas avant le changement → avant nil, comparaison quand même produite")
    func aucunRepasAvant() {
        let entrees = repas(nombre: 5, bons: 5, dose: 6, joursDecalage: 1)
        let comparaison = CalculDoseRatioChangement.comparer(entrees: entrees, dateChangement: changement)
        #expect(comparaison?.avant == nil)
        #expect(comparaison?.apres.effectif == 5)
    }

    @Test("Date de changement reportée telle quelle")
    func dateChangementReportee() {
        let entrees = repas(nombre: 5, bons: 1, dose: 6, joursDecalage: 1)
        #expect(CalculDoseRatioChangement.comparer(entrees: entrees, dateChangement: changement)?.dateChangement == changement)
    }
}
