//
//  HistoriqueParametresTests.swift
//  DiavizTests
//
//  Enregistreur d'historique des paramètres — prérequis de la frise des
//  périodes (docs/analyses/C1 — Frise des périodes.md § 2). Règles
//  vérifiées : seule une vraie transition valeur → valeur différente est
//  enregistrée, jamais la configuration initiale (nil → valeur), et une
//  rafale de saisies au stepper ne produit qu'une ligne.
//

import Foundation
import Testing
@testable import Diaviz

@MainActor
struct HistoriqueParametresTests {

    private typealias H = HistoriqueParametres

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let dejeuner = CleParametre(parametre: .ratioDejeuner)
    private let correction = CleParametre(parametre: .facteurCorrection)
    private let course = CleParametre(parametre: .ratioSport, typeSport: TypeSport.course.rawValue)

    private func diff(_ cle: CleParametre, _ ancienne: Double?, _ nouvelle: Double?) -> H.Difference {
        H.Difference(cle: cle, ancienne: ancienne, nouvelle: nouvelle)
    }

    private func apres(_ secondes: TimeInterval) -> Date {
        t0.addingTimeInterval(secondes)
    }

    // MARK: - Différences brutes

    @Test func aucuneDifferenceQuandRienNeChange() {
        let instantane = H.Instantane(valeurs: [dejeuner: 12, correction: 40])
        #expect(H.differences(avant: instantane, apres: instantane).isEmpty)
    }

    @Test func differencesCouvrentAjoutRetraitEtModification() {
        let avant = H.Instantane(valeurs: [dejeuner: 12, correction: 40])
        let apres = H.Instantane(valeurs: [dejeuner: 11, course: 15])
        let resultat = H.differences(avant: avant, apres: apres)
        #expect(Set(resultat.map(\.cle)) == [dejeuner, correction, course])
        #expect(resultat.contains(diff(dejeuner, 12, 11)))
        #expect(resultat.contains(diff(correction, 40, nil)))
        #expect(resultat.contains(diff(course, nil, 15)))
    }

    @Test func instantaneReleveTousLesParametresDuProfil() {
        let profil = ProfilUtilisateur.parDefaut()
        profil.ratioUnique = 10
        profil.ratiosParMoment = RatiosParMoment(petitDejeuner: 8, dejeuner: 12, gouter: 15, diner: 11)
        profil.ratioCorrection = 35
        var sport = RatiosSport()
        sport.definir(18, pour: .course)
        profil.ratiosSport = sport

        let valeurs = H.Instantane(profil: profil).valeurs
        #expect(valeurs[CleParametre(parametre: .ratioUnique)] == 10)
        #expect(valeurs[CleParametre(parametre: .ratioPetitDejeuner)] == 8)
        #expect(valeurs[dejeuner] == 12)
        #expect(valeurs[CleParametre(parametre: .ratioGouter)] == 15)
        #expect(valeurs[CleParametre(parametre: .ratioDiner)] == 11)
        #expect(valeurs[correction] == 35)
        #expect(valeurs[course] == 18)
        #expect(valeurs[CleParametre(parametre: .fenetreEffetSport)] == RatiosSport.fenetreParDefaut)
    }

    // MARK: - Transitions

    @Test func configurationInitialeNEstPasEnregistree() {
        var sessions = H.SessionsEdition()
        #expect(sessions.decider(diff(dejeuner, nil, 12), a: t0) == .ignorer)
    }

    @Test func vraieTransitionCreeUneLigne() {
        var sessions = H.SessionsEdition()
        guard case let .creer(_, ancienne, nouvelle) = sessions.decider(diff(dejeuner, 12, 10), a: t0) else {
            Issue.record("transition 12 → 10 non enregistrée")
            return
        }
        #expect(ancienne == 12)
        #expect(nouvelle == 10)
    }

    @Test func valeurRetireeEstUneTransition() {
        var sessions = H.SessionsEdition()
        guard case let .creer(_, ancienne, nouvelle) = sessions.decider(diff(course, 18, nil), a: t0) else {
            Issue.record("retrait du ratio sport non enregistré")
            return
        }
        #expect(ancienne == 18)
        #expect(nouvelle == nil)
    }

    @Test func rafaleAuStepperNeProduitQuUneLigne() {
        var sessions = H.SessionsEdition()
        guard case let .creer(id, _, _) = sessions.decider(diff(dejeuner, 12, 11), a: t0) else {
            Issue.record("première saisie non enregistrée")
            return
        }
        #expect(sessions.decider(diff(dejeuner, 11, 10), a: apres(2)) == .prolonger(id: id, nouvelle: 10))
        #expect(sessions.decider(diff(dejeuner, 10, 9), a: apres(4)) == .prolonger(id: id, nouvelle: 9))
    }

    @Test func retourALaValeurDeDepartEffaceLaLigne() {
        var sessions = H.SessionsEdition()
        guard case let .creer(id, _, _) = sessions.decider(diff(dejeuner, 12, 11), a: t0) else {
            Issue.record("première saisie non enregistrée")
            return
        }
        #expect(sessions.decider(diff(dejeuner, 11, 12), a: apres(3)) == .supprimer(id: id))
        // Repartir dans l'autre sens dans la foulée recrée une ligne neuve,
        // toujours avec la valeur de départ de la session.
        guard case let .creer(nouvelId, ancienne, nouvelle) =
                sessions.decider(diff(dejeuner, 12, 13), a: apres(5)) else {
            Issue.record("nouvelle direction non enregistrée")
            return
        }
        #expect(nouvelId != id)
        #expect(ancienne == 12)
        #expect(nouvelle == 13)
    }

    @Test func saisiesEspaceesProduisentDeuxLignes() {
        var sessions = H.SessionsEdition()
        let fenetre = H.SessionsEdition.fenetreParDefaut
        guard case let .creer(premier, _, _) = sessions.decider(diff(dejeuner, 12, 11), a: t0) else {
            Issue.record("première saisie non enregistrée")
            return
        }
        guard case let .creer(second, ancienne, _) =
                sessions.decider(diff(dejeuner, 11, 10), a: apres(fenetre + 1)) else {
            Issue.record("saisie hors fenêtre fusionnée à tort")
            return
        }
        #expect(premier != second)
        #expect(ancienne == 11)
    }

    @Test func fenetreGlisseDepuisLaDerniereSaisie() {
        var sessions = H.SessionsEdition(fenetre: 60)
        guard case let .creer(id, _, _) = sessions.decider(diff(dejeuner, 12, 11), a: t0) else {
            Issue.record("première saisie non enregistrée")
            return
        }
        #expect(sessions.decider(diff(dejeuner, 11, 10), a: apres(50)) == .prolonger(id: id, nouvelle: 10))
        // 100 s après le début, mais 50 s après la saisie précédente.
        #expect(sessions.decider(diff(dejeuner, 10, 9), a: apres(100)) == .prolonger(id: id, nouvelle: 9))
    }

    @Test func reglagesInitiauxEnRafaleRestentIgnores() {
        // Onboarding : le premier appui fixe la valeur (nil → 41), les
        // suivants l'ajustent dans la foulée — tout reste de la configuration.
        var sessions = H.SessionsEdition()
        #expect(sessions.decider(diff(correction, nil, 41), a: t0) == .ignorer)
        #expect(sessions.decider(diff(correction, 41, 42), a: apres(1)) == .ignorer)
        #expect(sessions.decider(diff(correction, 42, 45), a: apres(2)) == .ignorer)
    }

    @Test func modificationUlterieureAUneConfigurationInitialeEstEnregistree() {
        var sessions = H.SessionsEdition()
        #expect(sessions.decider(diff(correction, nil, 40), a: t0) == .ignorer)
        let plusTard = apres(H.SessionsEdition.fenetreParDefaut + 1)
        guard case let .creer(_, ancienne, nouvelle) = sessions.decider(diff(correction, 40, 35), a: plusTard) else {
            Issue.record("changement après configuration non enregistré")
            return
        }
        #expect(ancienne == 40)
        #expect(nouvelle == 35)
    }

    @Test func parametresIndependantsOntChacunLeurSession() {
        var sessions = H.SessionsEdition()
        guard case let .creer(idDejeuner, _, _) = sessions.decider(diff(dejeuner, 12, 11), a: t0),
              case let .creer(idCorrection, _, _) = sessions.decider(diff(correction, 40, 35), a: apres(1)) else {
            Issue.record("deux paramètres distincts devraient créer deux lignes")
            return
        }
        #expect(idDejeuner != idCorrection)
    }

    @Test func oublierFermeLesSessions() {
        var sessions = H.SessionsEdition()
        _ = sessions.decider(diff(dejeuner, 12, 11), a: t0)
        sessions.oublier()
        guard case let .creer(_, ancienne, _) = sessions.decider(diff(dejeuner, 11, 10), a: apres(1)) else {
            Issue.record("une session oubliée ne doit pas être prolongée")
            return
        }
        #expect(ancienne == 11)
    }
}
