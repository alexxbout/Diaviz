//
//  FiltreCoucherTests.swift
//  DiavizTests
//
//  Filtrage par critères de contexte de la recherche « Comparer à ce soir ».
//  Les critères se combinent en ET ; chaque chip affiche l'effectif qui
//  resterait si elle était activée — c'est ce compteur qui rend le filtrage
//  utilisable sur ~60 nuits, il doit être exact.
//

import Foundation
import Testing
@testable import Diaviz

struct FiltreCoucherTests {

    // MARK: - Fabriques

    private func soir(
        glycemie: Int = 110,
        sport: SportResume? = nil,
        charge: ChargeActivite = .aucune,
        iob: Double? = nil
    ) -> SoirCoucher {
        SoirCoucher(
            id: UUID(), date: Fixtures.reference, dateNuit: Fixtures.reference,
            glycemie: glycemie, tendance: .stable,
            correction: nil, glucides: nil, sport: sport, iob: iob,
            charge: charge, categorieB1: nil,
            enHypo: false, delaiHypoMinutes: nil, issueCorrection: nil
        )
    }

    private func course(_ duree: Int = 45) -> SportResume {
        SportResume(type: "Course", intensite: "modéré", dureeMinutes: duree)
    }

    private func velo() -> SportResume {
        SportResume(type: "Vélo", intensite: "léger", dureeMinutes: 60)
    }

    // MARK: - Critères proposés

    @Test("Le type de sport n'est proposé que si une séance a eu lieu ce soir")
    func typeSportSeulementAvecSeance() {
        let avec = FiltreCoucher.criteres(charge: .intense, sport: course(), iob: nil)
        #expect(avec.contains(.typeSport("Course")))
        #expect(avec.contains(.sport(present: true)))

        let sans = FiltreCoucher.criteres(charge: .intense, sport: nil, iob: nil)
        #expect(sans.contains(.typeSport("Course")) == false)
        // Un soir sans sport se compare aux soirs sans sport, pas l'inverse.
        #expect(sans.contains(.sport(present: false)))
    }

    @Test("Les critères sont ancrés sur le contexte de ce soir, pas sur une valeur fixe")
    func criteresAncresSurCeSoir() {
        let criteres = FiltreCoucher.criteres(charge: .calme, sport: nil, iob: 1.4)
        #expect(criteres.contains(.charge(.calme)))
        #expect(criteres.contains(.insuline(active: true)))
        #expect(criteres.contains(.insuline(active: false)) == false)
    }

    // MARK: - Correspondance

    @Test("Chaque critère ne retient que les soirs qui lui correspondent")
    func correspondance() {
        let avecCourse = soir(sport: course(), charge: .intense, iob: 1.2)
        let avecVelo = soir(sport: velo(), charge: .calme)
        let sansRien = soir()

        #expect(CritereCoucher.sport(present: true).correspond(avecCourse))
        #expect(CritereCoucher.sport(present: true).correspond(sansRien) == false)
        #expect(CritereCoucher.sport(present: false).correspond(sansRien))

        #expect(CritereCoucher.typeSport("Course").correspond(avecCourse))
        #expect(CritereCoucher.typeSport("Course").correspond(avecVelo) == false)

        #expect(CritereCoucher.charge(.intense).correspond(avecCourse))
        #expect(CritereCoucher.charge(.intense).correspond(avecVelo) == false)

        #expect(CritereCoucher.insuline(active: true).correspond(avecCourse))
        #expect(CritereCoucher.insuline(active: true).correspond(sansRien) == false)
        #expect(CritereCoucher.insuline(active: false).correspond(sansRien))
    }

    // MARK: - Combinaison

    @Test("Aucun critère actif → tous les soirs passent")
    func sansCritereToutPasse() {
        let soirs = [soir(sport: course()), soir(), soir(charge: .intense)]
        #expect(FiltreCoucher.filtrer(soirs, par: []).count == 3)
    }

    @Test("Les critères se combinent en ET, jamais en OU")
    func combinaisonEt() {
        let soirs = [
            soir(sport: course(), charge: .intense),   // les deux
            soir(sport: course(), charge: .calme),     // sport seul
            soir(charge: .intense),                    // charge seule
            soir(),                                    // aucun
        ]

        let sportSeul = FiltreCoucher.filtrer(soirs, par: [.sport(present: true)])
        #expect(sportSeul.count == 2)

        let lesDeux = FiltreCoucher.filtrer(soirs, par: [.sport(present: true), .charge(.intense)])
        #expect(lesDeux.count == 1)
    }

    // MARK: - Compteur des chips

    @Test("Le compteur d'une chip annonce l'effectif restant si on l'ajoute")
    func compteurAnnonceLeCout() {
        let soirs = [
            soir(sport: course(), charge: .intense),
            soir(sport: course(), charge: .calme),
            soir(charge: .intense),
            soir(),
        ]

        // Depuis zéro critère : 2 soirs avec sport.
        #expect(FiltreCoucher.compteSiAjoute(.sport(present: true), dans: soirs, criteres: []) == 2)

        // Une fois « sport » posé, ajouter « semaine intense » n'en laisse qu'un.
        #expect(FiltreCoucher.compteSiAjoute(
            .charge(.intense), dans: soirs, criteres: [.sport(present: true)]
        ) == 1)
    }

    @Test("Le compteur d'une chip déjà active vaut l'effectif courant")
    func compteurChipActive() {
        let soirs = [soir(sport: course()), soir(sport: velo()), soir()]
        let actifs: Set<CritereCoucher> = [.sport(present: true)]

        #expect(FiltreCoucher.compteSiAjoute(.sport(present: true), dans: soirs, criteres: actifs)
                == FiltreCoucher.filtrer(soirs, par: actifs).count)
    }

    @Test("Un critère qui viderait la liste annonce 0 — l'UI le désactive")
    func compteurZeroSignaleImpasse() {
        let soirs = [soir(sport: course(), charge: .calme)]
        #expect(FiltreCoucher.compteSiAjoute(.charge(.intense), dans: soirs, criteres: []) == 0)
    }

    @Test("Corpus vide → compteurs à zéro, aucun crash")
    func corpusVide() {
        #expect(FiltreCoucher.filtrer([], par: [.sport(present: true)]).isEmpty)
        #expect(FiltreCoucher.compteSiAjoute(.sport(present: true), dans: [], criteres: []) == 0)
    }
}
