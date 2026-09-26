//
//  CalculChargeActiveTests.swift
//  DiavizTests
//
//  Charge active — stock de charge à décroissance exponentielle (demi-vie
//  24 h), bouts de marche soutenue, dédoublonnage et bande d'hystérésis.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculChargeActiveTests {

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }

    private func apport(_ charge: Double, plusHeures heures: Double) -> ContributionCharge {
        ContributionCharge(instant: Fixtures.instant(plusHeures: heures), charge: charge, source: .seance)
    }

    private func seance(finAPlusHeures heures: Double, dureeMin: Int = 60, intensite: IntensiteSport = .moderee) -> SeancePourCharge {
        SeancePourCharge(
            debut: Fixtures.instant(plusHeures: heures - Double(dureeMin) / 60),
            dureeMin: dureeMin, intensite: intensite, fcMoyenne: nil, typeActiviteHK: nil
        )
    }

    // MARK: - Décroissance

    @Test("Une séance perd la moitié de sa charge toutes les 24 h")
    func decroissanceDemiVie() {
        let apports = [apport(120, plusHeures: 0)]
        let a = { (h: Double) in CalculChargeActive.chargeActive(a: Fixtures.instant(plusHeures: h), contributions: apports) }
        #expect(abs(a(0) - 120) < 1e-9)
        #expect(abs(a(24) - 60) < 1e-9)
        #expect(abs(a(48) - 30) < 1e-9)
        #expect(abs(a(72) - 15) < 1e-9)
        #expect(abs(a(96) - 7.5) < 1e-9)
    }

    @Test("Une séance future ne compte pas encore")
    func seanceFutureIgnoree() {
        let apports = [apport(120, plusHeures: 5)]
        #expect(CalculChargeActive.chargeActive(a: Fixtures.reference, contributions: apports) == 0)
    }

    @Test("Les séances s'accumulent : lun/mer/ven → 120, 150, 157,5")
    func accumulation() {
        let apports = [apport(120, plusHeures: 0), apport(120, plusHeures: 48), apport(120, plusHeures: 96)]
        let a = { (h: Double) in CalculChargeActive.chargeActive(a: Fixtures.instant(plusHeures: h), contributions: apports) }
        #expect(abs(a(0) - 120) < 1e-9)
        #expect(abs(a(24) - 60) < 1e-9)
        #expect(abs(a(48) - 150) < 1e-9)
        #expect(abs(a(96) - 157.5) < 1e-9)
    }

    @Test("La moyenne analytique du stock coïncide avec un échantillonnage fin")
    func moyenneAnalytique() {
        let apports = [apport(120, plusHeures: -30), apport(80, plusHeures: 10), apport(60, plusHeures: 40)]
        let debut = Fixtures.reference
        let fin = Fixtures.instant(plusHeures: 72)
        let analytique = CalculChargeActive.moyenneChargeActive(de: debut, a: fin, contributions: apports)
        let pas = 72 * 60
        let echantillons = (0..<pas).map { i in
            CalculChargeActive.chargeActive(a: Fixtures.instant(plusMinutes: Double(i) + 0.5), contributions: apports)
        }
        let numerique = echantillons.reduce(0, +) / Double(pas)
        #expect(abs(analytique - numerique) / numerique < 0.001)
    }

    @Test("En régime établi, la moyenne du stock vaut charge quotidienne × demi-vie / ln2")
    func normaleMemeUnite() {
        // 120 points par jour pendant 60 jours : la normale doit valoir
        // 120 × 1,4427 ≈ 173, pas la somme hebdo / 7 = 120.
        let apports = (0..<60).map { apport(120, plusHeures: Double($0) * 24) }
        let moyenne = CalculChargeActive.moyenneChargeActive(
            de: Fixtures.instant(plusHeures: 30 * 24), a: Fixtures.instant(plusHeures: 58 * 24), contributions: apports
        )
        #expect(abs(moyenne - 120 / log(2)) / (120 / log(2)) < 0.01)
    }

    // MARK: - Pondération

    @Test("Intensité : FC moyenne interpolée si présente, sinon intensité saisie")
    func facteurIntensite() {
        func s(_ fc: Double?, _ intensite: IntensiteSport = .intense) -> SeancePourCharge {
            SeancePourCharge(debut: Fixtures.reference, dureeMin: 60, intensite: intensite, fcMoyenne: fc, typeActiviteHK: 37)
        }
        #expect(CalculChargeActive.facteurIntensite(s(nil)) == 3)
        #expect(CalculChargeActive.facteurIntensite(s(nil, .faible)) == 1)
        #expect(abs(CalculChargeActive.facteurIntensite(s(95)) - 1) < 1e-9)    // 50 % FCmax
        #expect(abs(CalculChargeActive.facteurIntensite(s(133)) - 2) < 1e-9)   // 70 %
        #expect(abs(CalculChargeActive.facteurIntensite(s(171)) - 3) < 1e-9)   // 90 %
        #expect(CalculChargeActive.facteurIntensite(s(60)) == 1)                // borné bas
        #expect(CalculChargeActive.facteurIntensite(s(200)) == 3)               // borné haut
    }

    @Test("Le type d'activité est capté mais pèse 1 partout")
    func coefficientTypeNeutre() {
        #expect(CalculChargeActive.coefficientType(nil) == 1)
        #expect(CalculChargeActive.coefficientType(37) == 1)   // running
        #expect(CalculChargeActive.coefficientType(20) == 1)   // strength
    }

    @Test("Un bout de marche pèse 0,75 × durée")
    func chargeMarche() {
        let bout = BoutMarche(debut: Fixtures.reference, fin: Fixtures.instant(plusMinutes: 40), pas: 4400)
        #expect(abs(CalculChargeActive.charge(bout) - 30) < 1e-9)
    }

    // MARK: - Bouts de marche

    private func minutes(_ pas: [Double], depuis debut: Date = Fixtures.reference) -> [PasMinute] {
        pas.enumerated().map { PasMinute(debut: debut.addingTimeInterval(Double($0.offset) * 60), pas: $0.element) }
    }

    @Test("10 minutes consécutives à ≥ 100 pas/min forment un bout")
    func boutDetecte() {
        let bouts = CalculChargeActive.boutsMarche(pasParMinute: minutes([40] + Array(repeating: 100, count: 12) + [30]))
        #expect(bouts.count == 1)
        #expect(bouts.first?.debut == Fixtures.instant(plusMinutes: 1))
        #expect(bouts.first?.fin == Fixtures.instant(plusMinutes: 13))
        #expect(bouts.first?.pas == 1200)
    }

    @Test("9 minutes soutenues ne suffisent pas")
    func boutTropCourt() {
        #expect(CalculChargeActive.boutsMarche(pasParMinute: minutes(Array(repeating: 120, count: 9))).isEmpty)
    }

    @Test("Une minute sous la cadence coupe le bout")
    func boutCoupeParCadence() {
        let pas = Array(repeating: 115.0, count: 6) + [80] + Array(repeating: 115.0, count: 6)
        #expect(CalculChargeActive.boutsMarche(pasParMinute: minutes(pas)).isEmpty)
    }

    @Test("Une minute absente de la série coupe le bout")
    func boutCoupeParTrou() {
        let avant = minutes(Array(repeating: 115, count: 6))
        let apres = minutes(Array(repeating: 115, count: 6), depuis: Fixtures.instant(plusMinutes: 7))
        #expect(CalculChargeActive.boutsMarche(pasParMinute: avant + apres).isEmpty)
        // Sans trou, 12 minutes : un bout.
        let continu = minutes(Array(repeating: 115, count: 12))
        #expect(CalculChargeActive.boutsMarche(pasParMinute: continu).count == 1)
    }

    @Test("Préfiltrage : paires de blocs de 10 min à ≥ 1 000 pas, fusionnées")
    func plagesCandidates() {
        // Blocs : 300 | 700 | 200 | 100 | 0 | 900 | 150 (0 = bloc absent).
        let valeurs: [Double] = [300, 700, 200, 100, 0, 900, 150]
        let blocs = valeurs.enumerated().compactMap { i, pas -> PasBloc? in
            pas > 0 ? PasBloc(debut: Fixtures.instant(plusMinutes: Double(i) * 10), pas: pas) : nil
        }
        let plages = CalculChargeActive.plagesCandidates(pasParBloc: blocs)
        // 300+700 = 1000 → [0, 20] ; 700+200 = 900 non ; 900+150 = 1050 → [50, 70],
        // à moins de 3 h l'une de l'autre : relues en une seule plage.
        #expect(plages == [
            DateInterval(start: Fixtures.instant(plusMinutes: 0), end: Fixtures.instant(plusMinutes: 70)),
        ])
        // Au-delà de 3 h d'écart, deux plages distinctes.
        let eloignes = [
            PasBloc(debut: Fixtures.instant(plusMinutes: 0), pas: 1000),
            PasBloc(debut: Fixtures.instant(plusMinutes: 300), pas: 1000),
        ]
        #expect(CalculChargeActive.plagesCandidates(pasParBloc: eloignes).count == 2)
    }

    @Test("Préfiltrage : un vrai bout de marche passe toujours le filtre")
    func plagesCandidatesSansFauxNegatif() {
        // Bout de 10 min à 100 pas/min à cheval sur deux blocs (6 + 4 min).
        let blocs = [
            PasBloc(debut: Fixtures.instant(plusMinutes: 0), pas: 600),
            PasBloc(debut: Fixtures.instant(plusMinutes: 10), pas: 400),
        ]
        let plages = CalculChargeActive.plagesCandidates(pasParBloc: blocs)
        let minutes = (4..<14).map { PasMinute(debut: Fixtures.instant(plusMinutes: Double($0)), pas: 100) }
        let dansPlages = minutes.filter { m in plages.contains { $0.contains(m.debut) } }
        #expect(CalculChargeActive.boutsMarche(pasParMinute: dansPlages).count == 1)
    }

    // MARK: - Dédoublonnage

    @Test("Un bout qui chevauche une séance enregistrée est écarté, un bout adjacent est gardé")
    func dedoublonnage() {
        let seance = DateInterval(start: Fixtures.instant(plusMinutes: 60), end: Fixtures.instant(plusMinutes: 120))
        let chevauche = BoutMarche(debut: Fixtures.instant(plusMinutes: 110), fin: Fixtures.instant(plusMinutes: 130), pas: 2000)
        let dedans = BoutMarche(debut: Fixtures.instant(plusMinutes: 70), fin: Fixtures.instant(plusMinutes: 90), pas: 2000)
        let adjacent = BoutMarche(debut: Fixtures.instant(plusMinutes: 120), fin: Fixtures.instant(plusMinutes: 135), pas: 1500)
        let avant = BoutMarche(debut: Fixtures.instant(plusMinutes: 10), fin: Fixtures.instant(plusMinutes: 25), pas: 1500)
        let gardes = CalculChargeActive.exclureChevauchements([chevauche, dedans, adjacent, avant], seances: [seance])
        #expect(gardes == [adjacent, avant])
    }

    // MARK: - Hystérésis

    @Test("Seuils : entrée à ±40 %, maintien jusqu'à ±25 %")
    func niveauVise() {
        #expect(CalculChargeActive.niveauVise(indice: 1.4, depuis: .normale) == .haute)
        #expect(CalculChargeActive.niveauVise(indice: 1.3, depuis: .normale) == .normale)
        #expect(CalculChargeActive.niveauVise(indice: 1.3, depuis: .haute) == .haute)
        #expect(CalculChargeActive.niveauVise(indice: 1.2, depuis: .haute) == .normale)
        #expect(CalculChargeActive.niveauVise(indice: 0.6, depuis: .normale) == .basse)
        #expect(CalculChargeActive.niveauVise(indice: 0.7, depuis: .normale) == .normale)
        #expect(CalculChargeActive.niveauVise(indice: 0.7, depuis: .basse) == .basse)
        #expect(CalculChargeActive.niveauVise(indice: 0.8, depuis: .basse) == .normale)
    }

    @Test("Entrée en charge haute : 3 jours consécutifs au-delà de +40 %")
    func entreeHaute() {
        #expect(CalculChargeActive.niveau(indicesJournaliers: [1.0, 1.5, 1.5]).niveau == .normale)
        let r = CalculChargeActive.niveau(indicesJournaliers: [1.0, 1.5, 1.5, 1.5])
        #expect(r.niveau == .haute)
        #expect(r.depuisJours == 3)
    }

    @Test("Bande : entre +25 % et +40 %, on reste en charge haute")
    func maintienHaute() {
        let r = CalculChargeActive.niveau(indicesJournaliers: [1.5, 1.5, 1.5, 1.3, 1.3, 1.3, 1.3, 1.3])
        #expect(r.niveau == .haute)
        #expect(r.depuisJours == 8)
    }

    @Test("Sortie de charge haute : 3 jours sous +25 %, pas avant")
    func sortieHaute() {
        let base: [Double?] = [1.5, 1.5, 1.5]
        #expect(CalculChargeActive.niveau(indicesJournaliers: base + [1.1, 1.1]).niveau == .haute)
        #expect(CalculChargeActive.niveau(indicesJournaliers: base + [1.1, 1.1, 1.3, 1.1]).niveau == .haute)
        let r = CalculChargeActive.niveau(indicesJournaliers: base + [1.1, 1.1, 1.1])
        #expect(r.niveau == .normale)
        #expect(r.depuisJours == 3)
    }

    @Test("Symétrie en bas : entrée à −40 %, maintien jusqu'à −25 %, sortie au-dessus")
    func hysteresisBasse() {
        let entree: [Double?] = [0.55, 0.55, 0.55]
        #expect(CalculChargeActive.niveau(indicesJournaliers: entree).niveau == .basse)
        #expect(CalculChargeActive.niveau(indicesJournaliers: entree + [0.7, 0.7, 0.7, 0.7]).niveau == .basse)
        #expect(CalculChargeActive.niveau(indicesJournaliers: entree + [0.8, 0.8, 0.8]).niveau == .normale)
    }

    @Test("Un jour sans indice remet le compteur à zéro")
    func jourSansIndice() {
        #expect(CalculChargeActive.niveau(indicesJournaliers: [1.5, 1.5, nil, 1.5]).niveau == .normale)
    }

    // MARK: - Assemblage et dégradation

    @Test("Sans historique suffisant → pas assez de recul")
    func pasAssezDeRecul() {
        let maintenant = Fixtures.instant(plusHeures: 24 * 80)
        let seances = [seance(finAPlusHeures: 24 * 79)]
        let sansDebut = CalculChargeActive.analyser(
            seances: seances, bouts: [], debutHistorique: nil, maintenant: maintenant, calendrier: utc)
        #expect(sansDebut.etat == .pasAssezDeRecul)
        let recent = CalculChargeActive.analyser(
            seances: seances, bouts: [], debutHistorique: Fixtures.instant(plusHeures: 24 * 50),
            maintenant: maintenant, calendrier: utc)
        #expect(recent.etat == .pasAssezDeRecul)
    }

    @Test("Aucune activité sur la fenêtre de référence → pas de normale, pas de « charge basse »")
    func aucuneActivite() {
        let r = CalculChargeActive.analyser(
            seances: [], bouts: [], debutHistorique: Fixtures.reference,
            maintenant: Fixtures.instant(plusHeures: 24 * 80), calendrier: utc)
        #expect(r.etat == .aucuneActiviteDeReference)
    }

    @Test("Pas non lus → charge sur les séances seules, signalée partielle")
    func chargePartielle() {
        let r = CalculChargeActive.analyser(
            seances: [], bouts: nil, debutHistorique: Fixtures.reference,
            maintenant: Fixtures.instant(plusHeures: 24 * 80), calendrier: utc)
        #expect(r.marcheIncluse == false)
        let complet = CalculChargeActive.analyser(
            seances: [], bouts: [], debutHistorique: Fixtures.reference,
            maintenant: Fixtures.instant(plusHeures: 24 * 80), calendrier: utc)
        #expect(complet.marcheIncluse)
    }

    @Test("Régime régulier → niveau normal ; arrêt prolongé → charge basse")
    func regimeRegulierPuisArret() {
        // Une séance d'1 h chaque jour à 18 h pendant 100 jours.
        let seances = (0..<100).map { seance(finAPlusHeures: Double($0) * 24 + 18) }
        let pendant = CalculChargeActive.analyser(
            seances: seances, bouts: [], debutHistorique: Fixtures.reference,
            maintenant: Fixtures.instant(plusHeures: 99 * 24 + 20), calendrier: utc)
        guard case let .disponible(_, niveau, _) = pendant.etat else {
            Issue.record("indice attendu"); return
        }
        #expect(niveau == .normale)

        // Arrêt : 6 jours sans séance après les 100 jours.
        let apres = CalculChargeActive.analyser(
            seances: seances, bouts: [], debutHistorique: Fixtures.reference,
            maintenant: Fixtures.instant(plusHeures: 105 * 24 + 20), calendrier: utc)
        guard case let .disponible(indice, niveauApres, _) = apres.etat else {
            Issue.record("indice attendu"); return
        }
        #expect(indice < 0.6)
        #expect(niveauApres == .basse)
    }

    // MARK: - Contexte partagé

    /// Séance d'1 h à 18 h chaque jour pendant 100 jours, puis arrêt 6 jours.
    private func contexteRegulierPuisArret() -> (ContexteChargeActive, Date) {
        let seances = (0..<100).map { seance(finAPlusHeures: Double($0) * 24 + 18) }
        let bouts = [BoutMarche(debut: Fixtures.instant(plusHeures: 104 * 24 + 9), fin: Fixtures.instant(plusHeures: 104 * 24 + 9.5), pas: 3300)]
        let maintenant = Fixtures.instant(plusHeures: 105 * 24 + 20)
        return (CalculChargeActive.contexte(
            seances: seances, bouts: bouts, debutHistorique: Fixtures.reference,
            maintenant: maintenant, calendrier: utc
        ), maintenant)
    }

    @Test("Contexte : un jour, un niveau — la lecture à n'importe quelle heure du jour donne le même niveau")
    func contexteNiveauStableDansLaJournee() {
        let (contexte, maintenant) = contexteRegulierPuisArret()
        #expect(contexte.jours.count == CalculChargeActive.horizonJours)
        let jourPasse = Fixtures.instant(plusHeures: 80 * 24)
        let matin = contexte.synthese(a: jourPasse.addingTimeInterval(8 * 3600)).niveau
        let soir = contexte.synthese(a: jourPasse.addingTimeInterval(22 * 3600)).niveau
        #expect(matin == .normale)
        #expect(matin == soir)
        #expect(contexte.niveau(le: jourPasse) == .normale)
        #expect(contexte.synthese(a: maintenant).niveau == .basse)
        #expect(contexte.niveauxParJour[utc.startOfDay(for: maintenant)] == .basse)
    }

    @Test("Contexte : faits bruts par jour (séances et marche en minutes)")
    func contexteFaitsJournaliers() {
        let (contexte, maintenant) = contexteRegulierPuisArret()
        let jourSeance = contexte.jour(contenant: Fixtures.instant(plusHeures: 99 * 24 + 12))
        #expect(jourSeance?.nombreSeances == 1)
        #expect(jourSeance?.minutesSeances == 60)
        #expect(jourSeance?.minutesMarche == 0)
        let jourMarche = contexte.jour(contenant: Fixtures.instant(plusHeures: 104 * 24 + 12))
        #expect(jourMarche?.nombreSeances == 0)
        #expect(jourMarche?.minutesMarche == 30)
        #expect(contexte.jours.last?.jour == utc.startOfDay(for: maintenant))
    }

    @Test("Contexte : indice moyen d'une semaine régulière ≈ 1")
    func contexteIndiceMoyen() {
        let (contexte, _) = contexteRegulierPuisArret()
        let debut = Fixtures.instant(plusHeures: 70 * 24)
        let indice = contexte.indiceMoyen(de: debut, a: debut.addingTimeInterval(7 * 86_400))
        #expect(indice.map { abs($0 - 1) < 0.05 } == true)
        #expect(contexte.indiceMoyen(de: Fixtures.instant(plusHeures: 24), a: Fixtures.instant(plusHeures: 48)) == nil)
    }

    @Test("Niveaux successifs : inconnu avant le premier indice, puis rejoué")
    func niveauxSuccessifs() {
        let r = CalculChargeActive.niveauxSuccessifs(indicesJournaliers: [nil, nil, 1.0, 1.5, 1.5, 1.5])
        #expect(r.map(\.niveau) == [nil, nil, .normale, .normale, .normale, .haute])
        #expect(r.last?.depuisJours == 3)
    }

    @Test("Début d'historique : la plus tardive des deux sources présentes")
    func debutHistorique() {
        let ancien = Fixtures.reference
        let recent = Fixtures.instant(plusHeures: 24 * 400)
        #expect(CalculChargeActive.debutHistorique(premierPas: ancien, premiereSeance: recent) == recent)
        #expect(CalculChargeActive.debutHistorique(premierPas: recent, premiereSeance: ancien) == recent)
        #expect(CalculChargeActive.debutHistorique(premierPas: nil, premiereSeance: ancien) == ancien)
        #expect(CalculChargeActive.debutHistorique(premierPas: ancien, premiereSeance: nil) == ancien)
        #expect(CalculChargeActive.debutHistorique(premierPas: nil, premiereSeance: nil) == nil)
    }

    @Test("L'indice affiché est celui du jour (même lecture que le niveau), pas la valeur à l'instant")
    func indiceAfficheDuJour() {
        let (contexte, maintenant) = contexteRegulierPuisArret()
        let jourPasse = Fixtures.instant(plusHeures: 80 * 24)
        let apresSeance = contexte.synthese(a: jourPasse.addingTimeInterval(18.5 * 3600))
        guard case let .disponible(indice, _, _) = apresSeance.etat else {
            Issue.record("indice attendu"); return
        }
        let duJour = contexte.jour(contenant: jourPasse)?.indice
        // Juste après la séance, l'indice lu reste la moyenne de la journée,
        // proche de 1 — loin du pic instantané du stock.
        #expect(abs(indice - 1) < 0.3)
        #expect(duJour.map { abs($0 - 1) < 0.1 } == true)
        guard case let .disponible(indiceMaintenant, _, _) = contexte.synthese(a: maintenant).etat else {
            Issue.record("indice attendu"); return
        }
        #expect(indiceMaintenant == contexte.jours.last?.indice)
    }

    @Test("Cache des bouts : anciens avant la coupure + relus après, sans doublon à cheval")
    func fusionnerBouts() {
        let coupure = Fixtures.instant(plusHeures: 48)
        let ancien = BoutMarche(debut: Fixtures.instant(plusHeures: 10), fin: Fixtures.instant(plusHeures: 10.5), pas: 3300)
        let aCheval = BoutMarche(debut: Fixtures.instant(plusMinutes: 48 * 60 - 10), fin: Fixtures.instant(plusMinutes: 48 * 60 + 15), pas: 2750)
        let troncRelu = BoutMarche(debut: coupure, fin: Fixtures.instant(plusMinutes: 48 * 60 + 15), pas: 1650)
        let nouveau = BoutMarche(debut: Fixtures.instant(plusHeures: 50), fin: Fixtures.instant(plusHeures: 50.25), pas: 1650)
        let perime = BoutMarche(debut: Fixtures.instant(plusHeures: 60), fin: Fixtures.instant(plusHeures: 60.2), pas: 1300)
        let fusion = CalculChargeActive.fusionnerBouts(
            cache: [ancien, aCheval, perime], nouveaux: [troncRelu, nouveau], coupure: coupure
        )
        #expect(fusion == [ancien, aCheval, nouveau])
    }

    @Test("Référence en faits : séances et marche par semaine sur la fenêtre de référence")
    func referenceEnFaits() {
        let (contexte, maintenant) = contexteRegulierPuisArret()
        // Fenêtre = 4 semaines se terminant 7 j avant : une séance d'1 h par jour.
        let r = contexte.referenceEnFaits(a: maintenant)
        #expect(r?.seancesParSemaine == 7)
        #expect(r?.minutesSeancesParSemaine == 420)
        #expect(r?.minutesMarcheParSemaine == 0)
        #expect(ContexteChargeActive.vide.referenceEnFaits(a: maintenant) == nil)
    }
}
