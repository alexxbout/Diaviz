//
//  AssembleurReponseRepasTests.swift
//  DiavizTests
//
//  R1 — verdict par repas, règle « excursion + retour » sur la fenêtre
//  T-1h → T+4h. C'est le chiffre le plus visible de l'app (couleur de la row
//  du journal) et l'entrée du mining du ratio : un verdict faux se propage.
//

import Foundation
import Testing
@testable import Diaviz

struct AssembleurReponseRepasTests {

    private let repas = Fixtures.reference
    /// Horloge assez tardive pour que la fenêtre soit réputée captable
    /// (T+4h + 3h de délai Dexcom).
    private let maintenantTardif = Fixtures.instant(plusHeures: 12)

    // MARK: - Fabriques

    /// 49 mesures de T0 à T+4h (pas 5 min) — couverture complète de la
    /// portion post-repas.
    private func courbePostRepas(_ transformation: (inout [Int]) -> Void = { _ in }) -> [Int] {
        var valeurs = Array(repeating: 120, count: 49)
        transformation(&valeurs)
        return valeurs
    }

    private func echantillons(_ valeurs: [Int], depuisMinutes debut: Double = 0)
        -> [(date: Date, valeur: Int)] {
        Fixtures.serie(depuis: repas.addingTimeInterval(debut * 60), valeurs: valeurs)
    }

    private func reponse(
        _ valeurs: [Int],
        depuisMinutes debut: Double = 0,
        seuils: SeuilsGlycemiques = SeuilsGlycemiques()
    ) -> ReponseGlycemique? {
        let etat = AssembleurReponseRepas.analyser(
            heureRepas: repas,
            aUneInjection: true,
            echantillons: echantillons(valeurs, depuisMinutes: debut),
            maintenant: maintenantTardif,
            seuils: seuils
        )
        guard case .disponible(let reponse) = etat else { return nil }
        return reponse
    }

    // MARK: - États non analysables

    @Test("Repas sans injection → aucune analyse, même avec une courbe complète")
    func sansInjection() {
        let etat = AssembleurReponseRepas.analyser(
            heureRepas: repas,
            aUneInjection: false,
            echantillons: echantillons(courbePostRepas()),
            maintenant: maintenantTardif
        )
        guard case .sansInjection = etat else {
            Issue.record("attendu .sansInjection")
            return
        }
    }

    /// 48 mesures attendues sur [T0, T+4h] ; 39 présentes = 81 % (au-dessus
    /// du seuil de 80 %), 38 = 79 % (en dessous).
    @Test("Couverture juste au-dessus du seuil → analyse disponible")
    func couvertureSuffisante() {
        #expect(reponse(Array(repeating: 120, count: 39)) != nil)
    }

    @Test("Couverture juste sous le seuil → pas d'analyse")
    func couvertureInsuffisante() {
        #expect(reponse(Array(repeating: 120, count: 38)) == nil)
    }

    @Test("Fenêtre pas encore captable → en attente, avec le délai restant")
    func enAttenteAvecDelai() {
        let etat = AssembleurReponseRepas.analyser(
            heureRepas: repas,
            aUneInjection: true,
            echantillons: echantillons(Array(repeating: 120, count: 10)),
            maintenant: Fixtures.instant(plusHeures: 5)
        )
        guard case .enAttente(let minutesRestantes) = etat else {
            Issue.record("attendu .enAttente")
            return
        }
        // Captable à T+7h, horloge à T+5h → 2h restantes.
        #expect(minutesRestantes == 120)
    }

    @Test("Délai de capture écoulé sans couverture → données manquantes")
    func donneesManquantes() {
        let etat = AssembleurReponseRepas.analyser(
            heureRepas: repas,
            aUneInjection: true,
            echantillons: echantillons(Array(repeating: 120, count: 10)),
            maintenant: Fixtures.instant(plusHeures: 7)
        )
        guard case .donneesManquantes = etat else {
            Issue.record("attendu .donneesManquantes")
            return
        }
    }

    @Test("Aucun échantillon → données manquantes une fois le délai écoulé")
    func aucunEchantillon() {
        let etat = AssembleurReponseRepas.analyser(
            heureRepas: repas, aUneInjection: true, echantillons: [], maintenant: maintenantTardif
        )
        guard case .donneesManquantes = etat else {
            Issue.record("attendu .donneesManquantes")
            return
        }
    }

    // MARK: - Verdict

    @Test("Pic resté en cible et aucune hypo → bon")
    func picEnCible() {
        #expect(reponse(courbePostRepas())?.verdict == .bon)
    }

    @Test("Pic exactement à la cible haute (180) → bon")
    func picExactementCibleHaute() {
        #expect(reponse(courbePostRepas { $0[6] = 180 })?.verdict == .bon)
    }

    @Test("Excursion jamais refermée → mauvais")
    func excursionJamaisRefermee() {
        #expect(reponse(Array(repeating: 200, count: 49))?.verdict == .mauvais)
    }

    @Test("Pic exactement à 250 → mauvais, même avec retour rapide")
    func picExactement250() {
        #expect(reponse(courbePostRepas { $0[6] = 250 })?.verdict == .mauvais)
    }

    @Test("Hypo post-repas → mauvais, même sans excursion haute")
    func hypoPostRepas() {
        #expect(reponse(courbePostRepas { $0[10] = 69 })?.verdict == .mauvais)
    }

    @Test("Minimum exactement au seuil hypo (70) → pas une hypo")
    func minimumExactementSeuilHypo() {
        #expect(reponse(courbePostRepas { $0[10] = 70 })?.verdict == .bon)
    }

    @Test("Excursion modérée refermée rapidement → bon")
    func excursionRefermeeRapidement() {
        #expect(reponse(courbePostRepas { $0[6] = 200 })?.verdict == .bon)
    }

    @Test("Pic à 220 refermé rapidement → moyen (retour rapide réservé aux pics < 220)")
    func picALaBorneDuRetourRapide() {
        #expect(reponse(courbePostRepas { $0[6] = 219 })?.verdict == .bon)
        #expect(reponse(courbePostRepas { $0[6] = 220 })?.verdict == .moyen)
    }

    /// Le retour en cible est mesuré depuis **le repas**, pas depuis le pic —
    /// 120 min pile compte encore comme un retour rapide.
    @Test("Retour en cible à exactement 2h → bon ; 5 min plus tard → moyen")
    func borneDuRetourRapide() {
        let aDeuxHeures = courbePostRepas { valeurs in
            valeurs[6] = 200                       // pic à 30 min
            for index in 7...23 { valeurs[index] = 190 }
            valeurs[24] = 180                      // retour à 120 min pile
        }
        #expect(reponse(aDeuxHeures)?.verdict == .bon)

        let cinqMinutesPlusTard = courbePostRepas { valeurs in
            valeurs[6] = 200
            for index in 7...24 { valeurs[index] = 190 }
            valeurs[25] = 180                      // retour à 125 min
        }
        #expect(reponse(cinqMinutesPlusTard)?.verdict == .moyen)
    }

    @Test("Hypo avant le repas : hors du verdict, mais gardée dans la courbe")
    func hypoAvantRepasIgnoree() {
        var valeurs = Array(repeating: 60, count: 12)   // T-1h → T-5min
        valeurs += courbePostRepas()
        let resultat = reponse(valeurs, depuisMinutes: -60)

        #expect(resultat?.verdict == .bon)
        #expect(resultat?.pointsCgm.count == valeurs.count)
        #expect(resultat?.pointsCgm.first?.secondesDepuisRepas == -3600)
    }

    @Test("Points hors fenêtre T-1h → T+4h écartés")
    func pointsHorsFenetreEcartes() {
        // T-2h → T-1h05 (avant la fenêtre) puis T+4h05 → T+5h (après).
        let avant = echantillons(Array(repeating: 300, count: 12), depuisMinutes: -120)
        let pendant = echantillons(courbePostRepas())
        let apres = echantillons(Array(repeating: 300, count: 12), depuisMinutes: 245)

        let etat = AssembleurReponseRepas.analyser(
            heureRepas: repas, aUneInjection: true,
            echantillons: avant + pendant + apres, maintenant: maintenantTardif
        )
        guard case .disponible(let resultat) = etat else {
            Issue.record("attendu .disponible")
            return
        }
        #expect(resultat.pointsCgm.count == 49)
        #expect(resultat.valeurPic == 120)
    }

    @Test("Seuils du profil respectés (cible haute abaissée)")
    func seuilsDuProfil() {
        let valeurs = courbePostRepas { $0[6] = 160 }
        #expect(reponse(valeurs)?.verdict == .bon)
        // Avec une cible haute à 140, la même courbe devient une excursion
        // jamais refermée… sauf qu'elle redescend : retour rapide, pic < 220.
        let strict = SeuilsGlycemiques(hypoglycemie: 70, hyperglycemie: 140)
        #expect(reponse(valeurs, seuils: strict)?.verdict == .bon)
        // Une courbe entièrement au-dessus de la nouvelle cible, elle, sort.
        #expect(reponse(Array(repeating: 150, count: 49), seuils: strict)?.verdict == .mauvais)
    }

    // MARK: - Métriques de la réponse

    @Test("Pic et retour en cible reportés avec leurs instants")
    func metriquesDuPic() {
        let resultat = reponse(courbePostRepas { $0[6] = 200 })

        #expect(resultat?.valeurPic == 200)
        #expect(resultat?.tempsPic == TimeInterval(30 * 60))
        #expect(resultat?.tempsRetourCible == TimeInterval(35 * 60))
    }

    @Test("Aucun retour en cible → délai de retour absent")
    func aucunRetourEnCible() {
        let resultat = reponse(Array(repeating: 200, count: 49))
        #expect(resultat?.tempsRetourCible == nil)
    }
}
