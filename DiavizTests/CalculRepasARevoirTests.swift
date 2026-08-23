//
//  CalculRepasARevoirTests.swift
//  DiavizTests
//
//  Repas récurrents mal passés — regroupement par composition (signature),
//  verdict porté par le DERNIER repas du groupe, tolérance de portion en
//  seconde passe, masquage par occurrence précise (pas par groupe).
//

import Foundation
import Testing
@testable import Diaviz

struct CalculRepasARevoirTests {

    /// Ancrage temporel loin dans le futur relatif à `Fixtures.reference` —
    /// permet de placer des repas jusqu'à 46 jours avant sans dates négatives.
    private let maintenant = Fixtures.instant(Fixtures.reference, plusHeures: 24 * 100)

    private func heure(joursAvant j: Double) -> Date {
        maintenant.addingTimeInterval(-j * 86_400)
    }

    // MARK: - Fabriques

    private func aliment(_ nom: String, glucides: Int) -> Aliment {
        Aliment(emoji: "🍽", nom: nom, quantite: 100, glucides: glucides, insuline: 0)
    }

    private func pointsCgm(_ paires: [(minutes: Double, valeur: Double)]) -> [PointCgm] {
        paires.map { PointCgm(secondesDepuisRepas: $0.minutes * 60, valeur: $0.valeur) }
    }

    private func reponse(
        verdict: VerdictGlycemique,
        points: [(minutes: Double, valeur: Double)] = [(0, 120), (60, 150)],
        valeurPic: Double = 200,
        tempsPic: TimeInterval = 3_600
    ) -> ReponseGlycemique {
        ReponseGlycemique(
            pointsCgm: pointsCgm(points), verdict: verdict,
            valeurPic: valeurPic, tempsPic: tempsPic, tempsRetourCible: nil
        )
    }

    private func repasEtat(
        heure: Date,
        aliments: [Aliment],
        etat: EtatAnalyse?,
        exclu: Bool = false
    ) -> Repas {
        Repas(heure: heure, aliments: aliments, etatAnalyse: etat, exclureDesAnalyses: exclu)
    }

    private func repasVerdict(
        heure: Date,
        aliments: [Aliment],
        verdict: VerdictGlycemique,
        points: [(minutes: Double, valeur: Double)] = [(0, 120), (60, 150)],
        valeurPic: Double = 200,
        tempsPic: TimeInterval = 3_600,
        exclu: Bool = false
    ) -> Repas {
        repasEtat(
            heure: heure, aliments: aliments,
            etat: .disponible(reponse(verdict: verdict, points: points, valeurPic: valeurPic, tempsPic: tempsPic)),
            exclu: exclu
        )
    }

    /// Occurrence « mauvaise » — le cas nominal de la plupart des tests.
    private func repasMauvais(
        heure: Date,
        aliments: [Aliment],
        points: [(minutes: Double, valeur: Double)] = [(0, 120), (60, 250)],
        valeurPic: Double = 250,
        tempsPic: TimeInterval = 3_600,
        exclu: Bool = false
    ) -> Repas {
        repasVerdict(
            heure: heure, aliments: aliments, verdict: .mauvais,
            points: points, valeurPic: valeurPic, tempsPic: tempsPic, exclu: exclu
        )
    }

    private func analyser(
        _ repas: [Repas],
        occurrencesMinimales: Int = CalculRepasARevoir.occurrencesMinimalesParDefaut,
        idsMasques: Set<UUID> = [],
        maintenant: Date
    ) -> [RepasARevoir] {
        CalculRepasARevoir.analyser(
            repas: repas,
            horairesRepas: .defaut(),
            occurrencesMinimales: occurrencesMinimales,
            idsMasques: idsMasques,
            maintenant: maintenant
        )
    }

    // MARK: - Filtrage entrée

    @Test("Aucun repas → aucune carte")
    func aucunRepas() {
        #expect(analyser([], maintenant: maintenant).isEmpty)
    }

    @Test("Repas hors fenêtre 45 jours → ignoré")
    func horsFenetre() {
        let r = repasMauvais(heure: heure(joursAvant: 46), aliments: [aliment("Pizza", glucides: 60)])
        #expect(analyser([r], occurrencesMinimales: 1, maintenant: maintenant).isEmpty)
    }

    @Test("Repas exactement à la borne des 45 jours → inclus")
    func borneFenetre() {
        let r = repasMauvais(heure: heure(joursAvant: 45), aliments: [aliment("Pizza", glucides: 60)])
        #expect(analyser([r], occurrencesMinimales: 1, maintenant: maintenant).count == 1)
    }

    @Test("État d'analyse non disponible (attente / données manquantes / sans injection) → repas ignoré")
    func etatNonDisponible() {
        let aliments = [aliment("Riz", glucides: 40)]
        let attente = repasEtat(heure: heure(joursAvant: 1), aliments: aliments, etat: .enAttente(minutesRestantes: 30))
        let manquantes = repasEtat(heure: heure(joursAvant: 1), aliments: aliments, etat: .donneesManquantes)
        let sansInjection = repasEtat(heure: heure(joursAvant: 1), aliments: aliments, etat: .sansInjection)
        #expect(analyser([attente], occurrencesMinimales: 1, maintenant: maintenant).isEmpty)
        #expect(analyser([manquantes], occurrencesMinimales: 1, maintenant: maintenant).isEmpty)
        #expect(analyser([sansInjection], occurrencesMinimales: 1, maintenant: maintenant).isEmpty)
    }

    @Test("exclureDesAnalyses → repas totalement ignoré même s'il matche tout le reste")
    func exclureDesAnalyses() {
        let r1 = repasMauvais(heure: heure(joursAvant: 5), aliments: [aliment("Burger", glucides: 55)], exclu: true)
        let r2 = repasMauvais(heure: heure(joursAvant: 1), aliments: [aliment("Burger", glucides: 55)], exclu: true)
        #expect(analyser([r1, r2], maintenant: maintenant).isEmpty)
    }

    // MARK: - Signature de composition

    @Test("Aucun aliment ne dépasse le seuil → signature retombe sur le plus glucidique")
    func signatureRepliSurPlusGlucidique() {
        let r = Repas(heure: maintenant, aliments: [aliment("Chips", glucides: 8)])
        #expect(CalculRepasARevoir.signature(r) == ["chips"])
    }

    @Test("Signature normalise le nom (trim + minuscule) → deux repas équivalents partagent la même signature")
    func signatureNormalisation() {
        let r1 = Repas(heure: maintenant, aliments: [aliment("Pizza Margherita", glucides: 70)])
        let r2 = Repas(heure: maintenant, aliments: [aliment("  PIZZA MARGHERITA  ", glucides: 70)])
        #expect(CalculRepasARevoir.signature(r1) == CalculRepasARevoir.signature(r2))
    }

    // MARK: - Verdict du dernier repas

    @Test("Dernier repas du groupe en verdict mauvais, occurrences suffisantes → carte produite")
    func dernierMauvaisProduitCarte() {
        let r1 = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Pâtes bolognaise", glucides: 65)])
        let r2 = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Pâtes bolognaise", glucides: 65)])
        let resultat = analyser([r1, r2], maintenant: maintenant)
        #expect(resultat.count == 1)
        #expect(resultat.first?.idRepasSource == r2.id)
    }

    @Test("Dernier repas du groupe en bon/moyen/indéterminé → groupe entier ignoré")
    func dernierNonMauvaisIgnore() {
        // `ancien` reconstruit à chaque itération : un `Aliment` partagé
        // entre plusieurs `Repas` se retrouve réassigné au dernier
        // constructeur (relation à parent unique, cf. `Aliment.repasParent`).
        for verdict: VerdictGlycemique in [.bon, .moyen, .indetermine] {
            let ancien = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Pâtes bolognaise", glucides: 65)])
            let recent = repasVerdict(heure: heure(joursAvant: 2), aliments: [aliment("Pâtes bolognaise", glucides: 65)], verdict: verdict)
            #expect(analyser([ancien, recent], maintenant: maintenant).isEmpty)
        }
    }

    // MARK: - Tolérance de portion

    @Test("Occurrence à exactement ±15g du dernier → incluse")
    func toleranceGlucidesBornePile() {
        let ancien = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Riz", glucides: 75)])
        let recent = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Riz", glucides: 60)])
        let resultat = analyser([ancien, recent], maintenant: maintenant)
        #expect(resultat.count == 1)
        #expect(resultat.first?.nombreOccurrences == 2)
    }

    @Test("Occurrence à 16g du dernier → exclue, groupe retombe sous le seuil d'occurrences")
    func toleranceGlucidesDepassee() {
        let ancien = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Riz", glucides: 76)])
        let recent = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Riz", glucides: 60)])
        #expect(analyser([ancien, recent], maintenant: maintenant).isEmpty)
    }

    // MARK: - Seuil d'occurrences

    @Test("Exactement occurrencesMinimales après filtrage tolérance → carte produite")
    func occurrencesAuSeuil() {
        let r1 = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Riz", glucides: 60)])
        let r2 = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Riz", glucides: 60)])
        #expect(analyser([r1, r2], occurrencesMinimales: 2, maintenant: maintenant).count == 1)
    }

    @Test("Un en dessous d'occurrencesMinimales → pas de carte")
    func occurrencesSousLeSeuil() {
        let r1 = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Riz", glucides: 60)])
        #expect(analyser([r1], occurrencesMinimales: 2, maintenant: maintenant).isEmpty)
    }

    @Test("occurrencesMinimales personnalisé (3) respecté")
    func occurrencesMinimalesPersonnalise() {
        let r1 = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Riz", glucides: 60)])
        let r2 = repasMauvais(heure: heure(joursAvant: 5), aliments: [aliment("Riz", glucides: 60)])
        #expect(analyser([r1, r2], occurrencesMinimales: 3, maintenant: maintenant).isEmpty)

        let r3 = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Riz", glucides: 60)])
        #expect(analyser([r1, r2, r3], occurrencesMinimales: 3, maintenant: maintenant).count == 1)
    }

    // MARK: - Événement principal (courbe complète)

    @Test("Hypo tardive après 240 min → détectée comme événement principal malgré la troncature d'affichage")
    func hypoTardiveApres240Min() {
        let points: [(minutes: Double, valeur: Double)] = [
            (0, 120), (60, 220), (120, 180), (180, 130), (240, 90), (300, 55), (360, 80),
        ]
        let r1 = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Riz", glucides: 60)], points: points, valeurPic: 220, tempsPic: 3_600)
        let r2 = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Riz", glucides: 60)], points: points, valeurPic: 220, tempsPic: 3_600)
        let resultat = analyser([r1, r2], maintenant: maintenant)
        #expect(resultat.first?.estHypo == true)
        #expect(resultat.first?.evenementMinutes == 300)
        #expect(resultat.first?.evenementValeur == 55)
    }

    @Test("Pas d'hypo sur la courbe → pic utilisé comme événement principal")
    func picUtiliseQuandPasHypo() {
        let points: [(minutes: Double, valeur: Double)] = [(0, 140), (60, 260), (120, 220), (180, 200)]
        let r1 = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Riz", glucides: 60)], points: points, valeurPic: 260, tempsPic: 3_600)
        let r2 = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Riz", glucides: 60)], points: points, valeurPic: 260, tempsPic: 3_600)
        let resultat = analyser([r1, r2], maintenant: maintenant)
        #expect(resultat.first?.estHypo == false)
        #expect(resultat.first?.evenementValeur == 260)
        #expect(resultat.first?.evenementMinutes == 60)
    }

    // MARK: - Masquage par occurrence précise

    @Test("Masquer une occurrence puis nouvelle mauvaise occurrence du même repas → carte réapparaît")
    func masquageReapparaitSurNouvelleOccurrence() {
        let r1 = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Riz", glucides: 60)])
        let r2 = repasMauvais(heure: heure(joursAvant: 5), aliments: [aliment("Riz", glucides: 60)])

        let masque = analyser([r1, r2], idsMasques: [r2.id], maintenant: maintenant)
        #expect(masque.isEmpty)

        let r3 = repasMauvais(heure: heure(joursAvant: 1), aliments: [aliment("Riz", glucides: 60)])
        let apresNouvelleOccurrence = analyser([r1, r2, r3], idsMasques: [r2.id], maintenant: maintenant)
        #expect(apresNouvelleOccurrence.count == 1)
        #expect(apresNouvelleOccurrence.first?.idRepasSource == r3.id)
    }

    // MARK: - Tri et plafond

    @Test("Tri : hypos avant hypers, puis sévérité décroissante dans chaque catégorie")
    func triSeverite() {
        func groupe(nom: String, points: [(minutes: Double, valeur: Double)], pic: Double) -> (ancien: Repas, dernier: Repas) {
            let ancien = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment(nom, glucides: 60)], points: points, valeurPic: pic, tempsPic: 3_600)
            let dernier = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment(nom, glucides: 60)], points: points, valeurPic: pic, tempsPic: 3_600)
            return (ancien, dernier)
        }

        let hyperModere = groupe(nom: "A", points: [(0, 120), (60, 245)], pic: 245)
        let hyperSevere = groupe(nom: "B", points: [(0, 120), (60, 290)], pic: 290)
        let hypoLegere = groupe(nom: "C", points: [(0, 120), (60, 200), (120, 55)], pic: 200)
        let hypoProfonde = groupe(nom: "D", points: [(0, 120), (60, 200), (120, 40)], pic: 200)

        let tous = [hyperModere, hyperSevere, hypoLegere, hypoProfonde].flatMap { [$0.ancien, $0.dernier] }
        let resultat = analyser(tous, maintenant: maintenant)

        #expect(resultat.count == 4)
        #expect(resultat.map(\.idRepasSource) == [
            hypoProfonde.dernier.id, hypoLegere.dernier.id, hyperSevere.dernier.id, hyperModere.dernier.id,
        ])
    }

    @Test("Plus de 10 groupes valides → tri par sévérité puis troncature à 10")
    func plafondMaxCartes() {
        var derniers: [Repas] = []
        var tousLesRepas: [Repas] = []
        for i in 0..<11 {
            let pic = 200.0 + Double(i) // i = 10 → le plus sévère (pic le plus haut)
            let points: [(minutes: Double, valeur: Double)] = [(0, 120), (60, pic)]
            let ancien = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Repas\(i)", glucides: 60)], points: points, valeurPic: pic, tempsPic: 3_600)
            let dernier = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Repas\(i)", glucides: 60)], points: points, valeurPic: pic, tempsPic: 3_600)
            derniers.append(dernier)
            tousLesRepas.append(contentsOf: [ancien, dernier])
        }

        let resultat = analyser(tousLesRepas, maintenant: maintenant)
        #expect(resultat.count == 10)
        #expect(!resultat.contains { $0.idRepasSource == derniers[0].id })
        #expect(resultat.first?.idRepasSource == derniers[10].id)
    }

    // MARK: - Champs dérivés

    @Test("nombreOccurrences et glucidesMin/Max ne comptent que les occurrences dans la tolérance")
    func champsRefletentOccurrencesFiltrees() {
        let horsTolerance = repasMauvais(heure: heure(joursAvant: 20), aliments: [aliment("Riz", glucides: 100)])
        let dansTolerance = repasMauvais(heure: heure(joursAvant: 10), aliments: [aliment("Riz", glucides: 70)])
        let dernier = repasMauvais(heure: heure(joursAvant: 2), aliments: [aliment("Riz", glucides: 60)])

        let resultat = analyser([horsTolerance, dansTolerance, dernier], maintenant: maintenant)
        #expect(resultat.first?.nombreOccurrences == 2)
        #expect(resultat.first?.occurrencesPassees.count == 1)
        #expect(resultat.first?.glucidesMin == 60)
        #expect(resultat.first?.glucidesMax == 70)
    }
}
