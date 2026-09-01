//
//  CalculInventaireDonneesTests.swift
//  DiavizTests
//
//  Inventaire du hub : des décomptes, jamais un jugement. Un cumul faux ici
//  se lit comme un fait sur la page « Depuis le début ».
//

import Foundation
import Testing
@testable import Diaviz

struct CalculInventaireDonneesTests {

    private let calendrier = Calendar.current

    private var maintenant: Date {
        calendrier.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12)) ?? Date()
    }

    private func jour(_ joursAvant: Int, heure: Int = 9) -> Date {
        let base = calendrier.date(byAdding: .day, value: -joursAvant, to: maintenant) ?? maintenant
        return calendrier.date(bySettingHour: heure, minute: 0, second: 0, of: base) ?? base
    }

    private func analyser(_ entrees: [EntreeInventaire], glycemies: Int = 0) -> InventaireDonnees {
        CalculInventaireDonnees.analyser(entrees: entrees, nombreGlycemies: glycemies, maintenant: maintenant)
    }

    // MARK: - Hub vide

    @Test("Aucune entrée → inventaire vide, sans première saisie")
    func hubVide() {
        let inventaire = analyser([])
        #expect(inventaire.estVide)
        #expect(inventaire.premiereSaisie == nil)
        #expect(inventaire.joursCouverts == 0)
        #expect(inventaire.saisiesParJour.count == CalculInventaireDonnees.joursTrame)
        #expect(inventaire.saisiesParJour.allSatisfy { $0.saisies == 0 })
    }

    // MARK: - Cumuls par domaine

    @Test("Repas : compte, glucides cumulés et jours distincts")
    func cumulRepas() {
        let inventaire = analyser([
            EntreeInventaire(date: jour(0, heure: 8), domaine: .repas(glucides: 40)),
            EntreeInventaire(date: jour(0, heure: 20), domaine: .repas(glucides: 60)),
            EntreeInventaire(date: jour(3), domaine: .repas(glucides: 50)),
        ])
        #expect(inventaire.repas == 3)
        #expect(inventaire.glucidesTotal == 150)
        // Deux repas le même jour ne comptent qu'un jour couvert.
        #expect(inventaire.joursAvecRepas == 2)
    }

    @Test("Injections : unités cumulées et répartition lente / rapide")
    func cumulInjections() {
        let inventaire = analyser([
            EntreeInventaire(date: jour(1), domaine: .injection(unites: 6, lente: false)),
            EntreeInventaire(date: jour(1), domaine: .injection(unites: 22, lente: true)),
            EntreeInventaire(date: jour(2), domaine: .injection(unites: 4.5, lente: false)),
        ])
        #expect(inventaire.injections == 3)
        #expect(inventaire.injectionsLentes == 1)
        #expect(inventaire.injectionsRapides == 2)
        #expect(inventaire.unitesTotal == 32.5)
    }

    @Test("Sport et resucrages : durées cumulées, intentions séparées")
    func cumulSportEtResucrages() {
        let inventaire = analyser([
            EntreeInventaire(date: jour(1), domaine: .sport(minutes: 45)),
            EntreeInventaire(date: jour(4), domaine: .sport(minutes: 75)),
            EntreeInventaire(date: jour(1), domaine: .resucrage(preventif: true)),
            EntreeInventaire(date: jour(2), domaine: .resucrage(preventif: false)),
            EntreeInventaire(date: jour(2), domaine: .resucrage(preventif: false)),
        ])
        #expect(inventaire.seances == 2)
        #expect(inventaire.minutesSport == 120)
        #expect(inventaire.resucrages == 3)
        #expect(inventaire.resucragesPreventifs == 1)
        #expect(inventaire.resucragesCorrectifs == 2)
    }

    // MARK: - Ancienneté

    @Test("Première saisie = le fait le plus ancien, toutes familles confondues")
    func premiereSaisie() {
        let inventaire = analyser([
            EntreeInventaire(date: jour(2), domaine: .repas(glucides: 30)),
            EntreeInventaire(date: jour(9), domaine: .sport(minutes: 30)),
            EntreeInventaire(date: jour(5), domaine: .injection(unites: 3, lente: false)),
        ])
        #expect(inventaire.premiereSaisie == jour(9))
        // Inclusif : de J-9 à aujourd'hui, 10 jours.
        #expect(inventaire.joursCouverts == 10)
    }

    @Test("Une seule saisie aujourd'hui → 1 jour couvert, jamais 0")
    func unSeulJour() {
        let inventaire = analyser([EntreeInventaire(date: jour(0), domaine: .repas(glucides: 20))])
        #expect(inventaire.joursCouverts == 1)
    }

    // MARK: - Trame de régularité

    @Test("Trame : 14 jours, densité par jour, faits hors fenêtre exclus")
    func trameSaisie() {
        let inventaire = analyser([
            EntreeInventaire(date: jour(0, heure: 8), domaine: .repas(glucides: 40)),
            EntreeInventaire(date: jour(0, heure: 12), domaine: .injection(unites: 5, lente: false)),
            EntreeInventaire(date: jour(13), domaine: .repas(glucides: 40)),
            // J-20 : hors trame, mais toujours compté dans les totaux.
            EntreeInventaire(date: jour(20), domaine: .repas(glucides: 40)),
        ])
        let trame = inventaire.saisiesParJour
        #expect(trame.count == 14)
        #expect(trame.last?.saisies == 2)
        #expect(trame.first?.saisies == 1)
        #expect(inventaire.repas == 3)
    }

    // MARK: - Glycémies

    @Test("Les glycémies sont transmises telles quelles, sans entrer dans l'ancienneté")
    func glycemiesAPart() {
        let inventaire = CalculInventaireDonnees.analyser(
            entrees: [], nombreGlycemies: 3744, maintenant: maintenant
        )
        // Rien de saisi par l'utilisateur : l'inventaire reste « vide » même
        // si Apple Santé a fourni des milliers de mesures.
        #expect(inventaire.estVide)
    }
}
