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
            // Plancher capteur réel (Dexcom ne descend pas sous 40) : sans lui,
            // une dérive linéaire non clampée sur une fenêtre étendue par la
            // détection dawn (`extensionDawnMaxH`) file vers des valeurs
            // irréalistes qui gonflent artificiellement le coefficient de
            // variation et déclenchent `chaotique` à tort.
            valeur = max(40, valeur)
            return (date: instant, valeur: Int(valeur.rounded()))
        }
    }

    private func entrees(
        _ specs: [SpecNuit],
        rapides: [(heure: Date, dose: Double, correction: Bool)] = [],
        repas: [(heure: Date, glucides: Int)] = [],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)] = [],
        pauses: [(debut: Date, fin: Date?)] = []
    ) -> EntreesBasale {
        EntreesBasale(
            lectures: specs.flatMap(lectures),
            lentes: specs.filter(\.avecLente).map { (heure: lente($0.decalage), dose: $0.dose) },
            rapides: rapides,
            repas: repas,
            resucrages: resucrages,
            sports: [],
            pauses: pauses
        )
    }

    /// Resucrage correctif — le cas courant des fixtures.
    private func resucrage(_ heure: Date, _ glucides: Int) -> (heure: Date, glucides: Int, intention: IntentionResucrage) {
        (heure: heure, glucides: glucides, intention: .correctifHypo)
    }

    private func config(nuits: Int) -> ConfigBasale {
        var config = ConfigBasale()
        config.fenetreNuits = nuits
        return config
    }

    private func analyser(_ specs: [SpecNuit], fenetre: Int = 3,
                          rapides: [(heure: Date, dose: Double, correction: Bool)] = [],
                          repas: [(heure: Date, glucides: Int)] = [],
                          resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)] = [],
                          pauses: [(debut: Date, fin: Date?)] = [],
                          configure: ((inout ConfigBasale) -> Void)? = nil) -> AnalyseBasaleDetail {
        var cfg = config(nuits: fenetre)
        configure?(&cfg)
        return CalculAnalyseBasale.analyser(
            entrees: entrees(specs, rapides: rapides, repas: repas,
                             resucrages: resucrages, pauses: pauses),
            config: cfg,
            maintenant: maintenant
        )
    }

    /// Nuit unique la plus récente exploitable (décalage 1).
    private func nuitUnique(_ spec: SpecNuit,
                            rapides: [(heure: Date, dose: Double, correction: Bool)] = [],
                            repas: [(heure: Date, glucides: Int)] = [],
                            resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)] = [],
                            pauses: [(debut: Date, fin: Date?)] = []) -> NightChartData? {
        analyser([spec], fenetre: 2, rapides: rapides, repas: repas,
                 resucrages: resucrages, pauses: pauses)
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
        // Dérive assez marquée pour approcher l'hypo (garde-fou dérive-sans-
        // danger) sans être si abrupte qu'elle heurte le plancher capteur et
        // fausse le coefficient de variation sur la fenêtre étendue par la
        // détection dawn (`extensionDawnMaxH`).
        let analyse = analyser(
            (1...3).map { SpecNuit(decalage: $0, deriveParHeure: -12, depart: 150) }, fenetre: 4
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

    @Test("Hypo expliquée par l'IOB d'une correction récente → pas de signal basale")
    func hypoExpliqueeParIOB() {
        // Chantier 4 (28 sept.) : `aHypoProfonde` forçait « tendance basse »
        // même quand l'hypo n'était qu'une correction trop dosée — la
        // basale n'y était pour rien. Correction 3u à 90 min avant le creux :
        // IOB ≈ 1,6u au moment du creux (largement > seuil 0,5u), cette hypo
        // est expliquée. Même creux que `hypoProfondeJamaisStable`, mais avec
        // la correction le signal ne doit plus se déclencher.
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 15)]
        let correction = (heure: lente(1).addingTimeInterval(90 * 60), dose: 3.0, correction: true)
        let analyse = analyser([spec], fenetre: 2, rapides: [correction])

        #expect(analyse.nuitsAnalysees == 0)
        #expect(analyse.nightChartData.first?.categorieVerdict == nil)
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.iobResiduel.rawValue)
        #expect(analyse.hyposNocturnes == 1)
    }

    @Test("Passage bref sous 70 (2 relevés) → bruit capteur : nuit stable, aucune hypo comptée")
    func passageBrefNonCompte() {
        // Cas type : deux relevés à 68-69 sur une nuit plate
        // basculaient la nuit en « tendance basse » puis tout le verdict.
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 5, valeur: 68)]
        let analyse = analyser([spec], fenetre: 2)

        #expect(analyse.nightChartData.first?.categorieVerdict == .stable)
        #expect(analyse.hyposNocturnes == 0)
        #expect(analyse.nightChartData.first?.hypoRetenue == nil)
    }

    @Test("Passage bref sous le seuil sévère (54) → compté quand même")
    func passageBrefSevereCompte() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 0, valeur: 50)]
        let analyse = analyser([spec], fenetre: 2)

        #expect(analyse.nightChartData.first?.categorieVerdict == .tendanceBasse)
        #expect(analyse.hyposNocturnes == 1)
    }

    @Test("Épisode de 15 min sous 70 → hypo retenue, avec sa durée et son heure")
    func episodeQuinzeMinutesCompte() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 10, valeur: 65)]
        let analyse = analyser([spec], fenetre: 2)
        let nuit = analyse.nightChartData.first

        #expect(nuit?.categorieVerdict == .tendanceBasse)
        #expect(nuit?.hypoRetenue?.dureeMin == 15)
        #expect(nuit?.hypoRetenue?.heure == lente(1).addingTimeInterval(180 * 60))
        #expect(nuit?.hypoRetenue?.resucree == false)
    }

    @Test("Hypo en zone 2 (endormissement) : comptée, mais ne bascule pas la nuit")
    func hypoZone2NeBasculePas() {
        var spec = SpecNuit(decalage: 1)
        // Tôt dans la zone 2, et assez loin du début de zone 3 (L+2h) pour ne
        // pas tomber dans la fenêtre de rebond post-hypo de 90 min.
        spec.creux = [Creux(debutMinutes: 5, dureeMinutes: 15)]
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

    @Test("Rapide non correctif dans la nuit profonde → zone exclue (insuline hors basale)")
    func rapideNonCorrectifEnZone3() {
        // Trou comblé le 27 sept : une petite collation bolusée (sous le
        // seuil « repas copieux », pas une correction) faussait la pente
        // sans jamais exclure la zone. Toute rapide non-correctif dans la
        // zone exclut désormais la régression.
        let bolus = (heure: lente(1).addingTimeInterval(3 * 3600), dose: 2.0, correction: false)
        let analyse = analyser([SpecNuit(decalage: 1)], fenetre: 2, rapides: [bolus])
        #expect(analyse.nuitsAnalysees == 0)
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.bolusNonCorrectif.rawValue)
    }

    @Test("Repas copieux dans la nuit profonde → zone exclue ; au seuil exactement → conservée")
    func repasCopieuxEnZone3() {
        let heure = lente(1).addingTimeInterval(3 * 3600)
        let seuil = ConfigBasale().seuilRepasCopieux

        let copieux = analyser([SpecNuit(decalage: 1)], fenetre: 2, repas: [(heure: heure, glucides: seuil + 1)])
        #expect(copieux.nightChartData.first?.motifExclusion == RaisonExclusion.repasCopieux.rawValue)

        let limite = analyser([SpecNuit(decalage: 1)], fenetre: 2, repas: [(heure: heure, glucides: seuil)])
        #expect(limite.nuitsAnalysees == 1)
    }

    @Test("Dîner copieux avant la zone → exclue aussi : la digestion la traverse")
    func repasCopieuxAvantZone3() {
        let seuil = ConfigBasale().seuilRepasCopieux
        // Zone 3 démarre à L+2h ; un dîner 2 h avant la lente tombe donc 4 h
        // avant la zone, dans la fenêtre de digestion de 5 h.
        let diner = lente(1).addingTimeInterval(-2 * 3600)
        let analyse = analyser([SpecNuit(decalage: 1)], fenetre: 2,
                               repas: [(heure: diner, glucides: seuil + 1)])
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.repasCopieux.rawValue)

        // Au-delà de la fenêtre, le repas ne disqualifie plus rien.
        let tresTot = lente(1).addingTimeInterval(-4 * 3600)
        let conservee = analyser([SpecNuit(decalage: 1)], fenetre: 2,
                                 repas: [(heure: tresTot, glucides: seuil + 1)])
        #expect(conservee.nuitsAnalysees == 1)
    }

    @Test("Mode pause sur la nuit → zone exclue")
    func modePause() {
        let pause = (debut: soir(1), fin: Optional(soir(1).addingTimeInterval(12 * 3600)))
        let analyse = analyser([SpecNuit(decalage: 1)], fenetre: 2, pauses: [pause])

        #expect(analyse.nuitsAnalysees == 0)
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.modePause.rawValue)
    }

    @Test("Resucrage dans la nuit profonde → pente exclue, mais nuit comptée via le signal hypo")
    func resucrageEnZone3() {
        // Chantier 1 (27 sept) : une hypo resucrée dans la zone 3 excluait
        // avant la nuit ENTIÈRE du verdict — le déclencheur « hypo profonde
        // → tendance descendante immédiate » ne voyait jamais ces nuits,
        // le cas le plus courant (hypo traitée normalement). La pente reste
        // non fiable (motif de zone `resucrage`), mais la nuit compte
        // désormais dans `valides`, avec la catégorie forcée par l'hypo.
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 10)]   // en zone 3
        let prise = [resucrage(lente(1).addingTimeInterval(185 * 60), 15)]   // 15 g < seuil copieux
        let analyse = analyser([spec], fenetre: 2, resucrages: prise)

        // Motif de zone toujours affiché (pente non fiable)...
        let z3 = analyse.nightChartData.first?.zones.first { $0.zone == .nuitProfonde }
        #expect(z3?.exclusionReason == RaisonExclusion.resucrage.rawValue)
        // ...mais la nuit compte désormais dans le verdict, forcée « tendance
        // basse » par l'hypo, sans chiffre de dérive affichable.
        #expect(analyse.nuitsAnalysees == 1)
        #expect(analyse.nightChartData.first?.categorieVerdict == .tendanceBasse)
        #expect(analyse.nightChartData.first?.slopeZone3 == nil)
        #expect(analyse.nightChartData.first?.motifExclusion == nil)
        #expect(analyse.hyposNocturnes == 1)
    }

    @Test("Hyper corrigée en nuit profonde, sans explication → nuit comptée en tendance ascendante")
    func hyperCorrigeeEnZone3() {
        // Symétrique de `resucrageEnZone3` côté haut : une hyper non
        // expliquée (pas de dîner copieux, pas de rebond post-hypo) qui
        // reçoit une correction excluait avant la nuit entière — aucun
        // mécanisme miroir de `aHypoProfonde` n'existait côté hyper. La
        // pente reste non fiable (motif `bolusCorrection`), mais la nuit
        // compte désormais, forcée « tendance haute ».
        var spec = SpecNuit(decalage: 1, depart: 130)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 30, valeur: 220)]   // pic hyper en z3
        let correction = (heure: lente(1).addingTimeInterval(190 * 60), dose: 2.0, correction: true)
        let analyse = analyser([spec], fenetre: 2, rapides: [correction])

        let z3 = analyse.nightChartData.first?.zones.first { $0.zone == .nuitProfonde }
        #expect(z3?.exclusionReason == RaisonExclusion.bolusCorrection.rawValue)
        #expect(analyse.nuitsAnalysees == 1)
        #expect(analyse.nightChartData.first?.categorieVerdict == .tendanceHaute)
        #expect(analyse.nightChartData.first?.slopeZone3 == nil)
        #expect(analyse.nightChartData.first?.motifExclusion == nil)
    }

    @Test("Hyper en nuit profonde expliquée par un dîner copieux → pas de signal indépendant")
    func hyperExpliqueeParRepasCopieux() {
        // Une hyper qui n'est QUE de la digestion ne doit pas se travestir en
        // signal « basale trop faible » — sinon chaque dîner copieux
        // produirait une fausse tendance ascendante.
        var spec = SpecNuit(decalage: 1, depart: 130)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 30, valeur: 220)]
        let repasHeure = lente(1).addingTimeInterval(-1 * 3600)
        let analyse = analyser([spec], fenetre: 2, repas: [(heure: repasHeure, glucides: 150)])

        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.repasCopieux.rawValue)
        #expect(analyse.nuitsAnalysees == 0)
    }

    @Test("Resucrage préventif sans hypo → zone exclue proprement, aucun faux signal")
    func resucragePreventifSansHypo() {
        // Trou comblé le 27 sept : une prise préventive (jamais d'épisode
        // hypo, glycémie toujours ≥ 90) échappait avant à toute exclusion —
        // ni `repas` (sorti vers `resucrages`), ni `resucrageDans` (exigeait
        // un épisode hypo). La pente tournait polluée, sans motif affiché.
        let spec = SpecNuit(decalage: 1, depart: 90)
        let prise = [resucrage(lente(1).addingTimeInterval(180 * 60), 15)]
        let analyse = analyser([spec], fenetre: 2, resucrages: prise)

        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.resucrage.rawValue)
        #expect(analyse.nuitsAnalysees == 0)
    }

    @Test("Nuit chaotique (variabilité forte) → zone exclue")
    func nuitChaotique() {
        // Paliers bas (72, jamais sous le seuil hypo 70) dans un plateau haut
        // (178, jamais au-dessus du seuil hyper 180), répartis symétriquement
        // (~50/50) sur la fenêtre pour ne laisser aucune tendance linéaire
        // nette à retirer — chantier 2 (27 sept) classe désormais sur le CV
        // des **résidus** après retrait de la tendance, pas sur le CV brut :
        // une fenêtre avec une vraie tendance (même bruitée) ne doit plus se
        // faire jeter comme « chaotique » au même titre que du bruit pur.
        // `extensionDawnMaxH: 0` fige la fenêtre exacte (pas d'extension dawn
        // du 20 sept.) pour un calcul de CV reproductible à la main.
        var spec = SpecNuit(decalage: 1, depart: 178)
        spec.creux = [
            Creux(debutMinutes: 130, dureeMinutes: 52, valeur: 72),
            Creux(debutMinutes: 225, dureeMinutes: 53, valeur: 72),
        ]
        let analyse = analyser([spec], fenetre: 2) { $0.extensionDawnMaxH = 0 }
        #expect(analyse.nightChartData.first?.motifExclusion == RaisonExclusion.chaotique.rawValue)
    }

    @Test("Dérive forte et propre sur fenêtre étendue → jamais confondue avec du bruit (chantier 2)")
    func deriveForteNonChaotique() {
        // Cas qui motivait le chantier 2 : avant le retrait de tendance, une
        // dérive franche et propre pouvait dépasser le seuil de CV brut sur
        // une fenêtre étendue par la détection dawn (20 sept.) au même titre
        // que du vrai bruit — pire la basale, plus de chances d'être jetée
        // comme « chaotique ». Le CV des résidus (après retrait de la pente)
        // reste bas ici, quelle que soit l'amplitude de la dérive.
        let spec = SpecNuit(decalage: 1, deriveParHeure: -12, depart: 150)
        let analyse = analyser([spec], fenetre: 2)
        #expect(analyse.nightChartData.first?.motifExclusion != RaisonExclusion.chaotique.rawValue)
        #expect(analyse.nuitsAnalysees == 1)
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

    @Test("Resucrage correctif pendant l'hypo puis nouvelle hypo < 60 min → rechute")
    func resucrageAvecRechute() {
        var spec = SpecNuit(decalage: 1)
        spec.creux = [
            Creux(debutMinutes: 150, dureeMinutes: 10),
            Creux(debutMinutes: 190, dureeMinutes: 10)
        ]
        // Un repas ordinaire ne suffit plus : la rechute exige un resucrage
        // d'intention correctifHypo, saisi comme fait de hub distinct.
        let prise = [resucrage(lente(1).addingTimeInterval(155 * 60), 15)]
        let bilan = nuitUnique(spec, resucrages: prise)?.bilanHypos

        #expect(bilan?.resucrees == 1)
        #expect(bilan?.rechutes == 1)
        #expect(bilan?.enSerie == 0)
    }

    @Test("Resucrage compté jusqu'à 20 min après le début de l'épisode")
    func fenetreDeResucrage() {
        // Épisode le plus court qui compte encore (3 relevés = 15 min, règle
        // du consensus CGM) : il finit avant les 20 min, c'est l'élargissement
        // de la fenêtre que le test vérifie. Un creux de 2 relevés serait un
        // simple passage bref, plus compté du tout.
        var spec = SpecNuit(decalage: 1)
        spec.creux = [Creux(debutMinutes: 180, dureeMinutes: 10)]

        let dansLaFenetre = [resucrage(lente(1).addingTimeInterval(195 * 60), 15)]
        #expect(nuitUnique(spec, resucrages: dansLaFenetre)?.bilanHypos.resucrees == 1)

        let horsFenetre = [resucrage(lente(1).addingTimeInterval(215 * 60), 15)]
        #expect(nuitUnique(spec, resucrages: horsFenetre)?.bilanHypos.spontanees == 1)
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
