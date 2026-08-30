//
//  CalculAnalyseBasaleTests.swift
//  DiavizTests
//
//  B1 — détection basale. Le calculateur le plus lourd de l'app et celui
//  dont un verdict faux se voit le moins : la doc Eraser « B1 — Détection
//  basale » fixe la dérive ±30 mg/dL, les zones ancrées sur la lente, les
//  exclusions par zone, la taxonomie des hypos et la récence du verdict.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculAnalyseBasaleTests {

    private let cal = Calendar.current

    /// Horloge des tests : midi, donc jour métabolique en cours = ce jour-là.
    private var maintenant: Date {
        cal.date(bySettingHour: 12, minute: 0, second: 0, of: Fixtures.reference) ?? Fixtures.reference
    }

    /// 21h00 du soir de la nuit située `decalage` jours avant aujourd'hui —
    /// début de la grille d'affichage de cette nuit.
    private func soir(_ decalage: Int) -> Date {
        let jour = cal.date(byAdding: .day, value: -decalage, to: cal.startOfDay(for: maintenant))
            ?? maintenant
        return cal.date(bySettingHour: 21, minute: 0, second: 0, of: jour) ?? jour
    }

    /// Heure de la lente du soir de cette nuit (22h30).
    private func lente(_ decalage: Int) -> Date {
        soir(decalage).addingTimeInterval(1.5 * 3600)
    }

    // MARK: - Fabrique de nuits

    /// Un creux glycémique posé à `debutMinutes` après la lente.
    private struct Creux {
        let debutMinutes: Double
        let dureeMinutes: Double
        var valeur: Int = 60
    }

    private struct SpecNuit {
        let decalage: Int
        var deriveParHeure: Double = 0
        var depart: Int = 130
        var dose: Double = 18
        var avecLente = true
        var nombrePoints = 121          // 21h → 07h au pas de 5 min
        var creux: [Creux] = []
        var bruit: Double = 0
    }

    private func lectures(_ spec: SpecNuit) -> [(date: Date, valeur: Int)] {
        let debut = soir(spec.decalage)
        let ancre = lente(spec.decalage)
        return (0..<spec.nombrePoints).map { index in
            let instant = debut.addingTimeInterval(Double(index) * 300)
            let heures = Double(index) / 12
            var valeur = Double(spec.depart) + spec.deriveParHeure * heures
            if spec.bruit > 0 {
                valeur += spec.bruit * sin(Double(index) * 1.7)
            }
            for creux in spec.creux {
                let debutCreux = ancre.addingTimeInterval(creux.debutMinutes * 60)
                let finCreux = debutCreux.addingTimeInterval(creux.dureeMinutes * 60)
                if instant >= debutCreux && instant <= finCreux { valeur = Double(creux.valeur) }
            }
            return (date: instant, valeur: Int(valeur.rounded()))
        }
    }

    private func entrees(
        _ specs: [SpecNuit],
        rapides: [(heure: Date, dose: Double, correction: Bool)] = [],
        repas: [(heure: Date, glucides: Int)] = [],
        pauses: [(debut: Date, fin: Date?)] = []
    ) -> EntreesBasale {
        EntreesBasale(
            lectures: specs.flatMap(lectures),
            lentes: specs.filter(\.avecLente).map { (heure: lente($0.decalage), dose: $0.dose) },
            rapides: rapides,
            repas: repas,
            resucrages: [],
            sports: [],
            pauses: pauses
        )
    }

    private func config(nuits: Int) -> ConfigBasale {
        var config = ConfigBasale()
        config.fenetreNuits = nuits
        return config
    }

    private func analyser(_ specs: [SpecNuit], fenetre: Int = 3,
                          rapides: [(heure: Date, dose: Double, correction: Bool)] = [],
                          repas: [(heure: Date, glucides: Int)] = [],
                          pauses: [(debut: Date, fin: Date?)] = []) -> AnalyseBasaleDetail {
        CalculAnalyseBasale.analyser(
            entrees: entrees(specs, rapides: rapides, repas: repas, pauses: pauses),
            config: config(nuits: fenetre),
            maintenant: maintenant
        )
    }

    /// Nuit unique la plus récente exploitable (décalage 1).
    private func nuitUnique(_ spec: SpecNuit,
                            rapides: [(heure: Date, dose: Double, correction: Bool)] = [],
                            repas: [(heure: Date, glucides: Int)] = [],
                            pauses: [(debut: Date, fin: Date?)] = []) -> NightChartData? {
        analyser([spec], fenetre: 2, rapides: rapides, repas: repas, pauses: pauses)
            .nightChartData.first { $0.basaleDose > 0 || $0.motifExclusion != nil }
    }

    // MARK: - Classification de la dérive

    @Test("Dérive à exactement ±30 mg/dL → nuit stable")
    func deriveAuxBornes() {
        #expect(CalculAnalyseBasale.categorie(deriveMgDl: 30) == .stable)
        #expect(CalculAnalyseBasale.categorie(deriveMgDl: -30) == .stable)
        #expect(CalculAnalyseBasale.categorie(deriveMgDl: 0) == .stable)
    }

    @Test("Dérive au-delà des bornes → tendance basse ou haute")
    func deriveHorsBornes() {
        #expect(CalculAnalyseBasale.categorie(deriveMgDl: -30.01) == .tendanceBasse)
        #expect(CalculAnalyseBasale.categorie(deriveMgDl: 30.01) == .tendanceHaute)
    }

    @Test("Seuil de dérive paramétrable")
    func seuilDeriveParametrable() {
        #expect(CalculAnalyseBasale.categorie(deriveMgDl: -20, seuil: 15) == .tendanceBasse)
        #expect(CalculAnalyseBasale.categorie(deriveMgDl: -20, seuil: 25) == .stable)
    }

    // MARK: - Verdict d'ensemble

    @Test("Aucune donnée → données insuffisantes")
    func aucuneDonnee() {
        let analyse = CalculAnalyseBasale.analyser(
            entrees: EntreesBasale(lectures: [], lentes: [], rapides: [], repas: [], resucrages: [], sports: [], pauses: []),
            config: config(nuits: 3), maintenant: maintenant
        )
        #expect(analyse.verdict == .donneesInsuffisantes)
        #expect(analyse.nuitsAnalysees == 0)
        #expect(analyse.nightChartData.isEmpty)
        #expect(analyse.timeline.count == 3)
    }

    @Test("Moins de 3 nuits valides → données insuffisantes")
    func moinsDeTroisNuits() {
        let analyse = analyser([SpecNuit(decalage: 1), SpecNuit(decalage: 2)], fenetre: 4)
        #expect(analyse.nuitsAnalysees == 2)
        #expect(analyse.verdict == .donneesInsuffisantes)
    }

    @Test("3 nuits stables → basale adaptée")
    func troisNuitsStables() {
        let analyse = analyser((1...3).map { SpecNuit(decalage: $0) }, fenetre: 4)
        #expect(analyse.nuitsAnalysees == 3)
        #expect(analyse.nuitsStables == 3)
        #expect(analyse.verdict == .adaptee)
        #expect(analyse.enAmelioration == false)
    }

    @Test("3 nuits descendantes → tendance descendante (basale trop forte)")
    func nuitsDescendantes() {
        let analyse = analyser(
            (1...3).map { SpecNuit(decalage: $0, deriveParHeure: -20, depart: 180) }, fenetre: 4
        )
        #expect(analyse.nuitsTendanceBasse == 3)
        #expect(analyse.verdict == .tropHaute)
        #expect(analyse.deriveMoyenne < -30)
    }

    @Test("3 nuits ascendantes → tendance ascendante (basale trop faible)")
    func nuitsAscendantes() {
        let analyse = analyser(
            (1...3).map { SpecNuit(decalage: $0, deriveParHeure: 20, depart: 100) }, fenetre: 4
        )
        #expect(analyse.nuitsTendanceHaute == 3)
        #expect(analyse.verdict == .tropBasse)
        #expect(analyse.deriveMoyenne > 30)
    }

    @Test("Verdict porté par les 5 dernières nuits valides, pas par toute la fenêtre")
    func recenceDuVerdict() {
        // 8 nuits anciennes ascendantes, 5 récentes stables.
        let anciennes = (6...13).map { SpecNuit(decalage: $0, deriveParHeure: 20, depart: 100) }
        let recentes = (1...5).map { SpecNuit(decalage: $0) }
        let analyse = analyser(anciennes + recentes, fenetre: 14)

        #expect(analyse.nuitsAnalysees == 13)
        #expect(analyse.verdict == .adaptee)
        #expect(analyse.enAmelioration == true)
    }

    @Test("Hypo profonde récente → tendance descendante immédiate")
    func hypoProfondeForceLeVerdict() {
        var specs = (1...3).map { SpecNuit(decalage: $0) }
        // Creux 3h après la lente, donc en zone 3 (nuit profonde).
        specs[0].creux = [Creux(debutMinutes: 180, dureeMinutes: 15)]
        let analyse = analyser(specs, fenetre: 4)

        #expect(analyse.verdict == .tropHaute)
        #expect(analyse.hyposNocturnes >= 1)
    }

    @Test("Une nuit avec hypo profonde ne compte jamais « stable »")
    func hypoProfondeJamaisStable() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 15)]
        let analyse = analyser([spec], fenetre: 2)
        #expect(analyse.nightChartData.first?.categorieVerdict == .tendanceBasse)
    }

    @Test("Hypo en zone 2 (endormissement) : comptée, mais ne bascule pas la nuit")
    func hypoZone2NeBasculePas() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 30, dureeMinutes: 15)]   // 30 min après la lente
        let analyse = analyser([spec], fenetre: 2)

        #expect(analyse.hyposNocturnes == 1)
        #expect(analyse.nightChartData.first?.categorieVerdict == .stable)
    }

    // MARK: - Exclusions par zone

    @Test("CGM quasi absent → nuit sans données, sans graphique")
    func cgmQuasiAbsent() {
        let analyse = analyser([SpecNuit(decalage: 1, nombrePoints: 8)], fenetre: 2)
        #expect(analyse.nightChartData.isEmpty)
        #expect(analyse.nuitsAnalysees == 0)
    }

    @Test("Couverture de la nuit profonde sous 80 % → zone exclue")
    func couvertureZone3Insuffisante() {
        // Mesures arrêtées vers 01h55 : la nuit profonde va jusqu'à 04h.
        let analyse = analyser([SpecNuit(decalage: 1, nombrePoints: 60)], fenetre: 2)
        #expect(analyse.nuitsAnalysees == 0)
        #expect(analyse.nuitsExclues == 1)
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.cgmIncomplet.rawValue)
    }

    @Test("Nuit sans lente → non zonable")
    func nuitSansLente() {
        var spec = SpecNuit(decalage: 1)
        spec.avecLente = false
        let analyse = analyser([spec], fenetre: 2)

        #expect(analyse.nuitsAnalysees == 0)
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.pasDeLente.rawValue)
    }

    @Test("Bolus de correction dans la nuit profonde → zone exclue")
    func bolusCorrectionEnZone3() {
        let correction = (heure: lente(1).addingTimeInterval(3 * 3600), dose: 2.0, correction: true)
        let analyse = analyser([SpecNuit(decalage: 1)], fenetre: 2, rapides: [correction])

        #expect(analyse.nuitsAnalysees == 0)
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.bolusCorrection.rawValue)
    }

    @Test("Rapide non correctif dans la nuit profonde → zone conservée")
    func rapideNonCorrectifEnZone3() {
        let bolus = (heure: lente(1).addingTimeInterval(3 * 3600), dose: 2.0, correction: false)
        let analyse = analyser([SpecNuit(decalage: 1)], fenetre: 2, rapides: [bolus])
        #expect(analyse.nuitsAnalysees == 1)
    }

    @Test("Repas copieux dans la nuit profonde → zone exclue ; 50 g exactement → conservée")
    func repasCopieuxEnZone3() {
        let heure = lente(1).addingTimeInterval(3 * 3600)

        let copieux = analyser([SpecNuit(decalage: 1)], fenetre: 2, repas: [(heure: heure, glucides: 51)])
        #expect(copieux.nightChartData.first?.motifExclusion == RaisonExclusion.repasCopieux.rawValue)

        let limite = analyser([SpecNuit(decalage: 1)], fenetre: 2, repas: [(heure: heure, glucides: 50)])
        #expect(limite.nuitsAnalysees == 1)
    }

    @Test("Mode pause sur la nuit → zone exclue")
    func modePause() {
        let pause = (debut: soir(1), fin: Optional(soir(1).addingTimeInterval(12 * 3600)))
        let analyse = analyser([SpecNuit(decalage: 1)], fenetre: 2, pauses: [pause])

        #expect(analyse.nuitsAnalysees == 0)
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.modePause.rawValue)
    }

    @Test("Resucrage dans la nuit profonde → zone exclue, même sous le seuil copieux")
    func resucrageEnZone3() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 10)]   // en zone 3
        let resucrage = [(heure: lente(1).addingTimeInterval(185 * 60), glucides: 15)]   // 15 g < seuil copieux
        let analyse = analyser([spec], fenetre: 2, repas: resucrage)

        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.resucrage.rawValue)
        #expect(analyse.nuitsAnalysees == 0)
        // Le signal hypo reste conservé malgré l'exclusion de la zone.
        #expect(analyse.hyposNocturnes == 1)
    }

    @Test("Nuit chaotique (variabilité forte) → zone exclue")
    func nuitChaotique() {
        let analyse = analyser([SpecNuit(decalage: 1, depart: 120, bruit: 80)], fenetre: 2)
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.chaotique.rawValue)
    }

    // MARK: - Taxonomie des hypos

    @Test("Épisode court isolé → hypo simple, remontée spontanée")
    func hypoSimple() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 10)]
        let bilan = nuitUnique(spec)?.bilanHypos

        #expect(bilan?.episodes == 1)
        #expect(bilan?.prolongees == 0)
        #expect(bilan?.enSerie == 0)
        #expect(bilan?.rechutes == 0)
        #expect(bilan?.spontanees == 1)
        #expect(bilan?.episodesProfonds == 1)
    }

    @Test("Épisode continu de 30 min → hypo prolongée ; 25 min → non")
    func hypoProlongeeALaBorne() {
        var trenteMinutes = SpecNuit(decalage: 1)
        trenteMinutes.creux = [Creux(debutMinutes: 180, dureeMinutes: 30)]
        #expect(nuitUnique(trenteMinutes)?.bilanHypos.prolongees == 1)

        var vingtCinq = SpecNuit(decalage: 1)
        vingtCinq.creux = [Creux(debutMinutes: 180, dureeMinutes: 25)]
        #expect(nuitUnique(vingtCinq)?.bilanHypos.prolongees == 0)
    }

    @Test("Deux épisodes rapprochés sans repas → hypos en série")
    func hyposEnSerie() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [
            Creux(debutMinutes: 150, dureeMinutes: 10),
            Creux(debutMinutes: 190, dureeMinutes: 10)
        ]
        let bilan = nuitUnique(spec)?.bilanHypos

        #expect(bilan?.episodes == 2)
        #expect(bilan?.enSerie == 2)
        #expect(bilan?.rechutes == 0)
    }

    @Test("Deux épisodes espacés de plus d'une heure → ni série ni rechute")
    func hyposEspacees() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [
            Creux(debutMinutes: 120, dureeMinutes: 10),
            Creux(debutMinutes: 260, dureeMinutes: 10)
        ]
        let bilan = nuitUnique(spec)?.bilanHypos

        #expect(bilan?.episodes == 2)
        #expect(bilan?.enSerie == 0)
        #expect(bilan?.rechutes == 0)
    }

    @Test("Repas loggé pendant l'hypo puis nouvelle hypo < 60 min → rechute")
    func resucrageAvecRechute() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [
            Creux(debutMinutes: 150, dureeMinutes: 10),
            Creux(debutMinutes: 190, dureeMinutes: 10)
        ]
        let resucrage = [(heure: lente(1).addingTimeInterval(155 * 60), glucides: 15)]
        let bilan = nuitUnique(spec, repas: resucrage)?.bilanHypos

        #expect(bilan?.resucrees == 1)
        #expect(bilan?.rechutes == 1)
        #expect(bilan?.enSerie == 0)
    }

    @Test("Resucrage compté jusqu'à 20 min après le début de l'épisode")
    func fenetreDeResucrage() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 5)]

        let dansLaFenetre = [(heure: lente(1).addingTimeInterval(195 * 60), glucides: 15)]
        #expect(nuitUnique(spec, repas: dansLaFenetre)?.bilanHypos.resucrees == 1)

        let horsFenetre = [(heure: lente(1).addingTimeInterval(215 * 60), glucides: 15)]
        #expect(nuitUnique(spec, repas: horsFenetre)?.bilanHypos.spontanees == 1)
    }

    @Test("Les hypos de la zone d'aube restent comptées")
    func hypoEnZoneDawn() {
        var spec = SpecNuit(decalage: 1)
        // 22h30 + 6h15 = 04h45, soit après le début du dawn.
        spec.creux = [Creux(debutMinutes: 375, dureeMinutes: 10)]
        #expect(nuitUnique(spec)?.bilanHypos.episodes == 1)
    }

    // MARK: - Dose et fenêtre comparable

    @Test("Dose actuelle = dernier palier, sans changement à signaler si dose constante")
    func doseConstante() {
        let analyse = analyser((1...3).map { SpecNuit(decalage: $0) }, fenetre: 4)

        #expect(analyse.doseActuelle == 18)
        #expect(analyse.changementDoseRecent == nil)
        #expect(analyse.doseHistoriqueReel?.count == 1)
    }

    @Test("Changement de dose : nouveau palier détecté et nuits antérieures écartées")
    func changementDeDose() {
        let anciennes = (4...6).map { SpecNuit(decalage: $0, dose: 16) }
        let recentes = (1...3).map { SpecNuit(decalage: $0, dose: 18) }
        let analyse = analyser(anciennes + recentes, fenetre: 8)

        #expect(analyse.doseActuelle == 18)
        #expect(analyse.changementDoseRecent != nil)
        #expect(analyse.doseHistoriqueReel?.count == 2)
        // Seules les nuits depuis le changement entrent dans les compteurs ;
        // les 4 nuits antérieures de la fenêtre sont marquées.
        #expect(analyse.nuitsAnalysees == 3)
        #expect(analyse.timeline.filter(\.avantChangementDose).count == 4)
    }

    @Test("Changement de dose vieux de plus de 30 jours → plus signalé")
    func changementDeDoseAncien() {
        // Le palier courant (18u) a démarré il y a plus de 30 jours.
        let anciennes = (60...62).map { SpecNuit(decalage: $0, dose: 16) }
        let recentes = (40...42).map { SpecNuit(decalage: $0, dose: 18) }
        let analyse = analyser(anciennes + recentes, fenetre: 45)

        #expect(analyse.doseActuelle == 18)
        #expect(analyse.changementDoseRecent == nil)
    }

    // MARK: - Sorties d'affichage

    @Test("Nuit en cours jamais classée, mais présente dans la timeline")
    func nuitEnCours() {
        let analyse = analyser([SpecNuit(decalage: 0), SpecNuit(decalage: 1)], fenetre: 2)
        guard case .enCours = analyse.timeline.last?.etat else {
            Issue.record("la nuit du jour doit être « en cours »")
            return
        }
        #expect(analyse.nuitsAnalysees == 1)
    }

    @Test("Timeline ordonnée de la plus ancienne à la plus récente")
    func timelineOrdonnee() {
        let analyse = analyser((1...3).map { SpecNuit(decalage: $0) }, fenetre: 4)
        let dates = analyse.timeline.map(\.date)
        #expect(dates == dates.sorted())
        #expect(analyse.timeline.count == 4)
    }

    @Test("Graphiques triés du plus récent au plus ancien, grille de 121 points")
    func graphiquesTries() {
        let analyse = analyser((1...3).map { SpecNuit(decalage: $0) }, fenetre: 4)
        let dates = analyse.nightChartData.map(\.date)

        #expect(dates == dates.sorted(by: >))
        #expect(analyse.nightChartData.allSatisfy { $0.glucoseValues.count == 121 })
    }

    @Test("Les nuits retenues dans le verdict sont marquées")
    func nuitsRetenuesMarquees() {
        let analyse = analyser((1...7).map { SpecNuit(decalage: $0) }, fenetre: 8)
        #expect(analyse.nightChartData.filter(\.retenueDansVerdict).count == 5)
    }

    @Test("Glycémie moyenne au réveil reprise des nuits valides")
    func glycemieAuReveil() {
        let analyse = analyser((1...3).map { SpecNuit(decalage: $0, depart: 130) }, fenetre: 4)
        #expect(analyse.glycemieMoyenneReveil == 130)
    }
}
