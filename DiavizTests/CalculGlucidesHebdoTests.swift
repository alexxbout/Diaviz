//
//  CalculGlucidesHebdoTests.swift
//  DiavizTests
//
//  Moyenne quotidienne de glucides sur 2 fenêtres de 7 jours. Seul
//  garde-fou : 3 jours avec repas minimum par semaine, pour ne pas moyenner
//  sur un trou de saisie déguisé en jeûne.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculGlucidesHebdoTests {

    private let calendrier = Calendar.current

    /// Ancré à midi pour ne jamais chevaucher un changement de jour lors des
    /// décalages en heures des fabriques ci-dessous.
    private var aujourdhui: Date {
        calendrier.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12)) ?? Date()
    }

    /// Un repas `joursAvant` aujourd'hui (0 = aujourd'hui), à `heure`, avec
    /// `glucides` grammes.
    private func repas(joursAvant: Int, heure: Int = 8, glucides: Int, exclu: Bool = false) -> Repas {
        let jour = calendrier.date(byAdding: .day, value: -joursAvant, to: aujourdhui) ?? aujourdhui
        let date = calendrier.date(bySettingHour: heure, minute: 0, second: 0, of: jour) ?? jour
        return Repas(
            heure: date,
            aliments: [Aliment(emoji: "🍽", nom: "Repas type", quantite: 1, glucides: glucides, insuline: 0)],
            exclureDesAnalyses: exclu
        )
    }

    // MARK: - Garde-fou d'effectif

    @Test("Aucun repas → aucune synthèse")
    func aucunRepas() {
        #expect(CalculGlucidesHebdo.analyser(repas: [], maintenant: aujourdhui) == nil)
    }

    @Test("2 jours actifs dans une semaine (sous le seuil de 3) → aucune synthèse")
    func sousLeSeuil() {
        let repas = [
            repas(joursAvant: 0, glucides: 100), repas(joursAvant: 1, glucides: 100),
            repas(joursAvant: 7, glucides: 100), repas(joursAvant: 8, glucides: 100), repas(joursAvant: 9, glucides: 100),
        ]
        #expect(CalculGlucidesHebdo.analyser(repas: repas, maintenant: aujourdhui) == nil)
    }

    @Test("Exactement 3 jours actifs dans chaque semaine → synthèse produite")
    func seuilExact() {
        let repas =
            [0, 1, 2].map { self.repas(joursAvant: $0, glucides: 100) } +
            [7, 8, 9].map { self.repas(joursAvant: $0, glucides: 100) }
        #expect(CalculGlucidesHebdo.analyser(repas: repas, maintenant: aujourdhui) != nil)
    }

    // MARK: - Calcul de moyenne

    @Test("Moyenne = somme des jours actifs / nombre de jours actifs, jours sans repas ignorés")
    func moyenneSurJoursActifs() {
        // Cette semaine (J0..J6) : 3 jours actifs, 300 g au total → 100 g/j
        // en moyenne, pas 300/7.
        let repas =
            [self.repas(joursAvant: 0, glucides: 100), self.repas(joursAvant: 1, glucides: 100), self.repas(joursAvant: 2, glucides: 100)] +
            [7, 8, 9].map { self.repas(joursAvant: $0, glucides: 60) }
        let synthese = CalculGlucidesHebdo.analyser(repas: repas, maintenant: aujourdhui)
        #expect(synthese?.moyenneCetteSemaine == 100)
        #expect(synthese?.moyenneSemaineDerniere == 60)
    }

    @Test("Plusieurs repas le même jour sont sommés")
    func repasMemeJourSommes() {
        let repas =
            [repas(joursAvant: 0, heure: 8, glucides: 50), repas(joursAvant: 0, heure: 19, glucides: 70)] +
            [1, 2].map { self.repas(joursAvant: $0, glucides: 60) } +
            [7, 8, 9].map { self.repas(joursAvant: $0, glucides: 60) }
        let synthese = CalculGlucidesHebdo.analyser(repas: repas, maintenant: aujourdhui)
        // Jour 0 : 120 g, jours 1-2 : 60 g chacun → (120+60+60)/3 = 80.
        #expect(synthese?.moyenneCetteSemaine == 80)
    }

    @Test("Repas exclu des analyses n'entre pas dans la moyenne, ni dans le dénominateur de son jour")
    func repasExclu() {
        let repas =
            // Jour 0 : un seul repas, exclu — ce jour ne doit compter ni
            // dans la somme ni comme jour actif (sinon il pèserait pour un
            // 0 g silencieux plutôt que d'être simplement ignoré).
            [self.repas(joursAvant: 0, glucides: 100, exclu: true)] +
            [1, 2, 3].map { self.repas(joursAvant: $0, glucides: 60) } +
            [7, 8, 9].map { self.repas(joursAvant: $0, glucides: 60) }
        let synthese = CalculGlucidesHebdo.analyser(repas: repas, maintenant: aujourdhui)
        #expect(synthese?.moyenneCetteSemaine == 60)
    }

    @Test("Repas hors fenêtre de 14 jours ignoré")
    func horsFenetre() {
        let repas =
            [0, 1, 2].map { self.repas(joursAvant: $0, glucides: 100) } +
            [7, 8, 9].map { self.repas(joursAvant: $0, glucides: 100) } +
            [self.repas(joursAvant: 40, glucides: 9999)]
        let synthese = CalculGlucidesHebdo.analyser(repas: repas, maintenant: aujourdhui)
        #expect(synthese?.moyenneCetteSemaine == 100)
        #expect(synthese?.moyenneSemaineDerniere == 100)
    }

    // MARK: - Progression vers le seuil (placeholder d'accueil)

    @Test("Jours avec repas cette semaine : jours distincts des 7 derniers jours")
    func joursAvecRepasCetteSemaine() {
        let repas = [
            self.repas(joursAvant: 0, heure: 8, glucides: 40), self.repas(joursAvant: 0, heure: 19, glucides: 60),
            self.repas(joursAvant: 3, glucides: 60),
            // J-6 : dernier jour inclus dans la fenêtre.
            self.repas(joursAvant: 6, glucides: 60),
            // J-7 : hors fenêtre.
            self.repas(joursAvant: 7, glucides: 60),
        ]
        #expect(CalculGlucidesHebdo.joursAvecRepasCetteSemaine(repas: repas, maintenant: aujourdhui) == 3)
    }

    @Test("Jour dont le seul repas est exclu des analyses → pas compté")
    func joursAvecRepasIgnoreLesExclus() {
        let repas = [
            self.repas(joursAvant: 0, glucides: 100, exclu: true),
            self.repas(joursAvant: 1, glucides: 60),
        ]
        #expect(CalculGlucidesHebdo.joursAvecRepasCetteSemaine(repas: repas, maintenant: aujourdhui) == 1)
    }

    // MARK: - Série journalière

    @Test("Série de 14 points, jour sans repas à 0")
    func serieQuatorzeJours() {
        let repas = [0, 1, 2].map { self.repas(joursAvant: $0, glucides: 100) }
            + [7, 8, 9].map { self.repas(joursAvant: $0, glucides: 60) }
        let serie = CalculGlucidesHebdo.analyser(repas: repas, maintenant: aujourdhui)?.serieJournaliere
        #expect(serie?.count == 14)
        // J-13 (le plus ancien) n'a aucun repas.
        #expect(serie?.first?.totalGlucides == 0)
        // Dernier point = aujourd'hui (J0), 100 g.
        #expect(serie?.last?.totalGlucides == 100)
    }
}
