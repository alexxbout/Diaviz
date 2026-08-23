//
//  CalculRepasIsolesTests.swift
//  DiavizTests
//
//  Repas isolés mal passés — hors mining, hors regroupement composition.
//  Un repas qualifie s'il porte un contexte libre et/ou un ajustement ET
//  un verdict mauvais ; chaque repas produit sa propre carte, sans seuil
//  d'occurrences (voir CalculRepasARevoirTests pour le regroupement).
//

import Foundation
import Testing
@testable import Diaviz

struct CalculRepasIsolesTests {

    private let maintenant = Fixtures.instant(Fixtures.reference, plusHeures: 24 * 100)

    private func heure(joursAvant j: Double) -> Date {
        maintenant.addingTimeInterval(-j * 86_400)
    }

    // MARK: - Fabriques

    private func aliment(_ nom: String, glucides: Int) -> Aliment {
        Aliment(emoji: "🍽", nom: nom, quantite: 100, glucides: glucides, insuline: 0)
    }

    private func reponse(verdict: VerdictGlycemique, valeurPic: Double = 250, tempsPic: TimeInterval = 3_600) -> ReponseGlycemique {
        ReponseGlycemique(
            pointsCgm: [PointCgm(secondesDepuisRepas: 0, valeur: 120), PointCgm(secondesDepuisRepas: 3_600, valeur: valeurPic)],
            verdict: verdict, valeurPic: valeurPic, tempsPic: tempsPic, tempsRetourCible: nil
        )
    }

    private func ajustement(raison: RaisonAjustement = .sportRecent, valeur: Double = -1.5) -> Ajustement {
        Ajustement(raison: raison, valeur: valeur)
    }

    private func repas(
        heure: Date,
        aliments: [Aliment] = [Aliment(emoji: "🍕", nom: "Pizza", quantite: 100, glucides: 60, insuline: 0)],
        verdict: VerdictGlycemique? = .mauvais,
        contexteLibre: String? = nil,
        ajustements: [Ajustement] = [],
        exclu: Bool = false
    ) -> Repas {
        Repas(
            heure: heure, aliments: aliments,
            etatAnalyse: verdict.map { .disponible(reponse(verdict: $0)) },
            ajustements: ajustements, contexteLibre: contexteLibre, exclureDesAnalyses: exclu
        )
    }

    private func analyser(_ repas: [Repas], idsMasques: Set<UUID> = [], maintenant: Date) -> [RepasARevoir] {
        CalculRepasIsoles.analyser(
            repas: repas, horairesRepas: .defaut(), idsMasques: idsMasques, maintenant: maintenant
        )
    }

    // MARK: - Filtrage entrée

    @Test("Aucun repas → aucune carte")
    func aucunRepas() {
        #expect(analyser([], maintenant: maintenant).isEmpty)
    }

    @Test("Repas hors fenêtre 45 jours → ignoré")
    func horsFenetre() {
        let r = repas(heure: heure(joursAvant: 46), contexteLibre: "Voyage")
        #expect(analyser([r], maintenant: maintenant).isEmpty)
    }

    @Test("exclureDesAnalyses → repas totalement ignoré même s'il matche tout le reste")
    func exclureDesAnalyses() {
        let r = repas(heure: heure(joursAvant: 1), contexteLibre: "Voyage", exclu: true)
        #expect(analyser([r], maintenant: maintenant).isEmpty)
    }

    @Test("Ni contexte libre ni ajustement → repas ignoré")
    func niContexteNiAjustement() {
        let r = repas(heure: heure(joursAvant: 1))
        #expect(analyser([r], maintenant: maintenant).isEmpty)
    }

    // MARK: - Qualification (contexte / ajustement / verdict)

    @Test("Contexte libre seul + verdict mauvais → carte produite")
    func contexteLibreSeul() {
        let r = repas(heure: heure(joursAvant: 1), contexteLibre: "Repas au restaurant")
        let resultat = analyser([r], maintenant: maintenant)
        #expect(resultat.count == 1)
        #expect(resultat.first?.contexteAffiche == "Repas au restaurant")
        #expect(resultat.first?.badgesAjustements.isEmpty == true)
    }

    @Test("Ajustement seul + verdict mauvais → carte produite")
    func ajustementSeul() {
        let r = repas(heure: heure(joursAvant: 1), ajustements: [ajustement()])
        let resultat = analyser([r], maintenant: maintenant)
        #expect(resultat.count == 1)
        #expect(resultat.first?.contexteAffiche == nil)
        #expect(resultat.first?.badgesAjustements.count == 1)
    }

    @Test("Contexte libre ET ajustement à la fois → une seule carte, les deux blocs de badges")
    func contexteEtAjustementCombines() {
        let r = repas(
            heure: heure(joursAvant: 1),
            contexteLibre: "Fête entre amis",
            ajustements: [ajustement(raison: .repasGras, valeur: 1)]
        )
        let resultat = analyser([r], maintenant: maintenant)
        #expect(resultat.count == 1)
        #expect(resultat.first?.contexteAffiche == "Fête entre amis")
        #expect(resultat.first?.badgesAjustements.count == 1)
    }

    @Test("Verdict bon/moyen/indéterminé → jamais de carte, même avec contexte ou ajustement")
    func verdictNonMauvaisIgnore() {
        for verdict: VerdictGlycemique in [.bon, .moyen, .indetermine] {
            let r = repas(heure: heure(joursAvant: 1), verdict: verdict, contexteLibre: "Contexte", ajustements: [ajustement()])
            #expect(analyser([r], maintenant: maintenant).isEmpty)
        }
    }

    // MARK: - Occurrence unique (pas de récurrence)

    @Test("Chaque carte est une occurrence unique : nombreOccurrences == 1, occurrencesPassees vide")
    func occurrenceUnique() {
        let r1 = repas(heure: heure(joursAvant: 5), aliments: [aliment("Pizza", glucides: 60)], contexteLibre: "Contexte")
        let r2 = repas(heure: heure(joursAvant: 1), aliments: [aliment("Pizza", glucides: 60)], contexteLibre: "Contexte")
        let resultat = analyser([r1, r2], maintenant: maintenant)
        #expect(resultat.count == 2)
        #expect(resultat.allSatisfy { $0.nombreOccurrences == 1 })
        #expect(resultat.allSatisfy { $0.occurrencesPassees.isEmpty })
    }

    // MARK: - Masquage

    @Test("Masquer une carte par idRepasSource → n'affecte pas les autres repas isolés")
    func masquagePrecis() {
        let r1 = repas(heure: heure(joursAvant: 5), contexteLibre: "Contexte 1")
        let r2 = repas(heure: heure(joursAvant: 1), contexteLibre: "Contexte 2")
        let resultat = analyser([r1, r2], idsMasques: [r1.id], maintenant: maintenant)
        #expect(resultat.count == 1)
        #expect(resultat.first?.idRepasSource == r2.id)
    }

    // MARK: - Tri et plafond (délégués à CalculRepasARevoir)

    @Test("Plus de 10 repas isolés qualifiés → tri par sévérité puis troncature à 10")
    func plafondMaxCartes() {
        let reps: [Repas] = (0..<11).map { i in
            let pic = 200.0 + Double(i) // i = 10 → le plus sévère (pic le plus haut)
            return Repas(
                heure: heure(joursAvant: Double(i) + 1),
                aliments: [aliment("Repas\(i)", glucides: 60)],
                etatAnalyse: .disponible(reponse(verdict: .mauvais, valeurPic: pic)),
                contexteLibre: "Contexte \(i)"
            )
        }
        let resultat = analyser(reps, maintenant: maintenant)
        #expect(resultat.count == 10)
        #expect(!resultat.contains { $0.idRepasSource == reps[0].id })
        #expect(resultat.first?.idRepasSource == reps[10].id)
    }
}
