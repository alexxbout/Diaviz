//
//  EntreeAlimentDepuisRepasTests.swift
//  DiavizTests
//
//  Rouvrir un aliment enregistré pour modifier le repas : les glucides, le
//  nom et l'emoji restent ceux enregistrés tant que rien n'est retouché.
//

import Foundation
import Testing
@testable import Diaviz

@MainActor
struct EntreeAlimentDepuisRepasTests {

    private func aliment(quantite: Int, glucides: Int, insuline: Double = 0) -> Aliment {
        Aliment(emoji: "🍝", nom: "Produit inconnu du référentiel", quantite: quantite, glucides: glucides, insuline: insuline)
    }

    @Test("Sans fiche d'origine, les glucides enregistrés sont conservés")
    func glucidesConserves() {
        let entree = EntreeAliment(depuis: aliment(quantite: 130, glucides: 47))
        #expect(entree.quantiteGrammes == 130)
        #expect(abs(entree.glucides - 47) < 0.001)
    }

    @Test("Changer la quantité recalcule les glucides au prorata")
    func prorata() {
        var entree = EntreeAliment(depuis: aliment(quantite: 100, glucides: 40))
        entree.quantiteGrammes = 150
        #expect(abs(entree.glucides - 60) < 0.001)
    }

    @Test("Quantité nulle : les glucides ne sont pas perdus")
    func quantiteNulle() {
        let entree = EntreeAliment(depuis: aliment(quantite: 0, glucides: 15))
        #expect(abs(entree.glucides - 15) < 0.001)
    }

    @Test("Le nom et l'emoji enregistrés repartent tels quels")
    func nomEtEmojiFiges() {
        let source = aliment(quantite: 100, glucides: 40, insuline: 2)
        let retour = Aliment(depuis: EntreeAliment(depuis: source))
        #expect(retour.nom == source.nom)
        #expect(retour.emoji == source.emoji)
        #expect(retour.insuline == 2)
        #expect(retour.glucides == 40)
    }

    @Test("Une fiche reconstruite n'enregistre pas de faux code-barres")
    func pasDeFauxCode() {
        let retour = Aliment(depuis: EntreeAliment(depuis: aliment(quantite: 100, glucides: 40)))
        #expect(retour.codeProduitOFF == nil)
    }

    @Test("Sans dose, l'aliment repart sans insuline")
    func sansDose() {
        #expect(EntreeAliment(depuis: aliment(quantite: 100, glucides: 40)).doseInsuline == nil)
    }
}
