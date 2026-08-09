//
//  IOBCalculateurTests.swift
//  DiavizTests
//
//  Modèle exponentiel d'insuline active (Loop / OpenAPS). L'IOB est une
//  entrée de B2/B3 et du détail de soirée : une fraction restante fausse
//  déplace silencieusement un facteur « insuline encore active ».
//

import Foundation
import Testing
@testable import Diaviz

struct IOBCalculateurTests {

    private let dia: Double = 240      // 4 h en minutes
    private let pic: Double = 75

    // MARK: - Fraction restante

    @Test("Avant l'injection et à l'instant même : dose entière restante")
    func fractionAvantInjection() {
        #expect(IOBCalculateur.fractionRestante(minutes: 0, diaMinutes: dia, picMinutes: pic) == 1)
        #expect(IOBCalculateur.fractionRestante(minutes: -30, diaMinutes: dia, picMinutes: pic) == 1)
    }

    @Test("À la fin de la durée d'action et au-delà : plus rien d'actif")
    func fractionApresDIA() {
        #expect(IOBCalculateur.fractionRestante(minutes: dia, diaMinutes: dia, picMinutes: pic) == 0)
        #expect(IOBCalculateur.fractionRestante(minutes: dia + 60, diaMinutes: dia, picMinutes: pic) == 0)
    }

    @Test("Fraction bornée à [0, 1] sur toute la durée d'action")
    func fractionBornee() {
        for minutes in stride(from: 5.0, to: dia, by: 5) {
            let fraction = IOBCalculateur.fractionRestante(minutes: minutes, diaMinutes: dia, picMinutes: pic)
            #expect(fraction >= 0 && fraction <= 1, "fraction hors bornes à \(minutes) min : \(fraction)")
        }
    }

    @Test("Décroissance stricte de la fraction restante")
    func fractionDecroissante() {
        var precedente = IOBCalculateur.fractionRestante(minutes: 5, diaMinutes: dia, picMinutes: pic)
        for minutes in stride(from: 10.0, to: dia, by: 5) {
            let courante = IOBCalculateur.fractionRestante(minutes: minutes, diaMinutes: dia, picMinutes: pic)
            #expect(courante < precedente, "remontée de l'IOB à \(minutes) min")
            precedente = courante
        }
    }

    /// Le modèle exige `td > 2·tp` : un pic saisi trop tard est ramené à
    /// `0,45 × td`, sinon la formule diverge.
    @Test("Pic au-delà de 0,45 × DIA : clampé, pas divergent")
    func picClampe() {
        let clampe = IOBCalculateur.fractionRestante(minutes: 60, diaMinutes: dia, picMinutes: 200)
        let borne = IOBCalculateur.fractionRestante(minutes: 60, diaMinutes: dia, picMinutes: 0.45 * dia)
        #expect(clampe == borne)
        #expect(clampe.isFinite)
    }

    @Test("Pic d'action par type d'insuline")
    func picParTypeInsuline() {
        #expect(InsulineRapide.novorapid.picActionMinutes == 75)
        #expect(InsulineRapide.humalog.picActionMinutes == 75)
        #expect(InsulineRapide.apidra.picActionMinutes == 75)
        #expect(InsulineRapide.autre.picActionMinutes == 75)
        #expect(InsulineRapide.fiasp.picActionMinutes == 55)
        #expect(InsulineRapide.lyumjev.picActionMinutes == 55)
    }

    // MARK: - IOB total

    @Test("Aucune injection → IOB nul")
    func iobSansInjection() {
        let iob = IOBCalculateur.iob(
            a: Fixtures.reference, injections: [], diaHeures: 4, picMinutes: pic
        )
        #expect(iob == 0)
    }

    @Test("IOB = somme des résidus de chaque injection")
    func iobSomme() {
        let instant = Fixtures.instant(plusMinutes: 60)
        let injections = [
            InjectionPourIOB(heure: Fixtures.reference, dose: 4),
            InjectionPourIOB(heure: Fixtures.instant(plusMinutes: 30), dose: 2)
        ]
        let total = IOBCalculateur.iob(a: instant, injections: injections, diaHeures: 4, picMinutes: pic)

        let attendu = 4 * IOBCalculateur.fractionRestante(minutes: 60, diaMinutes: dia, picMinutes: pic)
            + 2 * IOBCalculateur.fractionRestante(minutes: 30, diaMinutes: dia, picMinutes: pic)
        #expect(abs(total - attendu) < 1e-9)
    }

    @Test("Injection déjà périmée (au-delà de la DIA) → n'entre plus dans l'IOB")
    func iobInjectionPerimee() {
        let injections = [InjectionPourIOB(heure: Fixtures.reference, dose: 6)]
        let iob = IOBCalculateur.iob(
            a: Fixtures.instant(plusHeures: 5), injections: injections, diaHeures: 4, picMinutes: pic
        )
        #expect(iob == 0)
    }

    /// Comportement documenté du calculateur : il ne filtre pas les
    /// injections futures (`t <= 0` → fraction 1). Ce sont les appelants
    /// (B2, B3, détail de soirée) qui bornent la liste sur `heure <= instant`.
    @Test("Injection postérieure à l'instant évalué : dose comptée entière")
    func iobInjectionFuture() {
        let injections = [InjectionPourIOB(heure: Fixtures.instant(plusMinutes: 60), dose: 3)]
        let iob = IOBCalculateur.iob(
            a: Fixtures.reference, injections: injections, diaHeures: 4, picMinutes: pic
        )
        #expect(iob == 3)
    }

    // MARK: - Courbe projetée

    @Test("Courbe : pas de 15 min, premier point à l'instant courant")
    func courbePasDeQuinzeMinutes() {
        let injections = [InjectionPourIOB(heure: Fixtures.reference, dose: 8)]
        let points = IOBCalculateur.courbe(
            injections: injections, depuis: Fixtures.reference, diaHeures: 4, picMinutes: pic
        )

        #expect(points.first?.minutesDepuisMaintenant == 0)
        #expect(points.first?.iob == 8)
        for (index, point) in points.enumerated() {
            #expect(point.minutesDepuisMaintenant == index * 15)
        }
    }

    @Test("Courbe décroissante puis coupée sous 0,05 u")
    func courbeCoupeeSousLeSeuil() {
        let injections = [InjectionPourIOB(heure: Fixtures.reference, dose: 8)]
        let points = IOBCalculateur.courbe(
            injections: injections, depuis: Fixtures.reference, diaHeures: 4, picMinutes: pic
        )

        // Aucun point intermédiaire sous le seuil : seul le dernier peut l'être.
        #expect(points.dropLast().allSatisfy { $0.iob >= 0.05 })
        #expect(points.last?.iob ?? 1 < 0.05)
        // La DIA est de 4 h : la courbe ne va jamais jusqu'à l'horizon de 6 h.
        #expect(points.last?.minutesDepuisMaintenant ?? 0 <= 240)
    }

    @Test("Courbe sans injection : le point « maintenant » est toujours gardé")
    func courbeSansInjection() {
        let points = IOBCalculateur.courbe(
            injections: [], depuis: Fixtures.reference, diaHeures: 4, picMinutes: pic
        )
        #expect(points.first?.minutesDepuisMaintenant == 0)
        #expect(points.first?.iob == 0)
        #expect(points.count == 2)   // « maintenant », puis coupure au point suivant
    }

    @Test("Horizon de projection paramétrable")
    func courbeHorizonParametrable() {
        let injections = [InjectionPourIOB(heure: Fixtures.reference, dose: 20)]
        let points = IOBCalculateur.courbe(
            injections: injections, depuis: Fixtures.reference,
            diaHeures: 4, picMinutes: pic, horizonMinutes: 60
        )
        #expect(points.last?.minutesDepuisMaintenant == 60)
    }
}
