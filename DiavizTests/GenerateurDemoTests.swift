//
//  GenerateurDemoTests.swift
//  DiavizTests
//
//  Cohérence du jeu fictif de l'app « Diaviz Démo » : reproductible, crédible,
//  et porteur de chaque élément de l'histoire que les captures du README
//  racontent (nuit avec hypo, pizza récurrente hors cible, repas
//  rapprochés, changement de lente et de ratio, séances avec FC).
//

import Foundation
import SwiftData
import Testing
@testable import Diaviz

@MainActor
struct GenerateurDemoTests {

    static let calendrier: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    /// 6 nov. 2026, 17 h 30 (Paris) : ancre fixe, indépendante de l'horloge.
    static let ancre = calendrier.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 17, minute: 30))!

    static let jeu = GenerateurDemo.generer(ancre: ancre, calendrier: calendrier)

    var jeu: JeuDemo { Self.jeu }
    var cal: Calendar { Self.calendrier }

    func jour(_ j: Int) -> Date {
        cal.date(byAdding: .day, value: j, to: cal.startOfDay(for: Self.ancre))!
    }

    func glycemies(de debut: Date, a fin: Date) -> [Int] {
        jeu.glycemies.filter { $0.date >= debut && $0.date <= fin }.map(\.valeur)
    }

    // MARK: Reproductibilité

    @Test("Même ancre → même jeu, valeur pour valeur")
    func reproductible() {
        let autre = GenerateurDemo.generer(ancre: Self.ancre, calendrier: cal)
        #expect(autre.glycemies.map(\.valeur) == jeu.glycemies.map(\.valeur))
        #expect(autre.glycemies.map(\.date) == jeu.glycemies.map(\.date))
        #expect(autre.repas.map(\.id) == jeu.repas.map(\.id))
        #expect(autre.injections.map(\.dose) == jeu.injections.map(\.dose))
        #expect(autre.resucrages.map(\.date) == jeu.resucrages.map(\.date))
        #expect(autre.sommeil.map(\.debut) == jeu.sommeil.map(\.debut))
    }

    @Test("Rien n'est daté après l'ancre")
    func rienDansLeFutur() {
        #expect(jeu.glycemies.allSatisfy { $0.date <= Self.ancre })
        #expect(jeu.repas.allSatisfy { $0.heure <= Self.ancre })
        #expect(jeu.injections.allSatisfy { $0.heure <= Self.ancre })
        #expect(jeu.seances.allSatisfy { $0.fin <= Self.ancre })
        #expect(jeu.sommeil.allSatisfy { $0.fin <= Self.ancre })
    }

    // MARK: Glycémie

    @Test("~3 mois de CGM toutes les 5 min, couverture ≥ 95 %, valeurs capteur")
    func couvertureCGM() throws {
        let premiere = try #require(jeu.glycemies.first?.date)
        #expect(premiere < jour(-88))
        let attendus = Self.ancre.timeIntervalSince(premiere) / 300
        #expect(Double(jeu.glycemies.count) / attendus >= 0.95)
        #expect(jeu.glycemies.allSatisfy { (40...400).contains($0.valeur) })
    }

    @Test("Profil glycémique crédible : majorité dans la cible, hypos et pics présents mais rares")
    func profilCredible() {
        let valeurs = jeu.glycemies.map(\.valeur)
        let n = Double(valeurs.count)
        let dansCible = Double(valeurs.filter { (70...180).contains($0) }.count) / n
        let sous70 = Double(valeurs.filter { $0 < 70 }.count) / n
        let sur250 = Double(valeurs.filter { $0 > 250 }.count) / n
        #expect(dansCible > 0.6 && dansCible < 0.92, "TIR \(dansCible)")
        #expect(sous70 > 0 && sous70 < 0.05, "TBR \(sous70)")
        #expect(sur250 > 0 && sur250 < 0.1, "> 250 : \(sur250)")
    }

    @Test("Aujourd'hui est une bonne journée (vitrine de l'accueil)")
    func aujourdhuiBonneJournee() {
        let valeurs = glycemies(de: jour(0), a: Self.ancre)
        #expect(!valeurs.isEmpty)
        let dansCible = Double(valeurs.filter { (70...180).contains($0) }.count) / Double(valeurs.count)
        #expect(dansCible >= 0.85, "TIR du jour \(dansCible)")
        #expect(valeurs.allSatisfy { $0 >= 70 })
    }

    // MARK: Repas et insuline

    @Test("Chaque bolus repas pointe vers un repas, chaque repas a son bolus")
    func bolusRepasCoherents() {
        let ids = Set(jeu.repas.map(\.id))
        let bolus = jeu.injections.filter { $0.type == .rapideRepas }
        #expect(bolus.allSatisfy { $0.repasId.map(ids.contains) == true })
        #expect(Set(bolus.compactMap(\.repasId)) == ids)
        for r in jeu.repas {
            let b = bolus.first { $0.repasId == r.id }
            #expect(b?.dose == r.dose)
            #expect(b?.heure == r.heure)
            #expect(r.dose >= 0.5 && r.dose <= 15)
            #expect(r.glucides > 0)
        }
    }

    @Test("Trois repas par jour au moins, aux heures habituelles")
    func rythmeRepas() {
        for j in -80 ... -1 {
            let duJour = jeu.repas.filter { cal.isDate($0.heure, inSameDayAs: jour(j)) }
            #expect(duJour.count >= 3, "J\(j) : \(duJour.count) repas")
            #expect(duJour.allSatisfy { (6...22).contains(cal.component(.hour, from: $0.heure)) })
        }
    }

    @Test("Une lente par soir : 18 u, puis 16 u à partir de J-28")
    func lente() {
        let lentes = jeu.injections.filter { $0.type == .lente }
        #expect(lentes.count >= 89)
        for l in lentes {
            let attendu = l.heure >= jour(JeuDemo.jourChangementLente) ? 16.0 : 18.0
            #expect(l.dose == attendu)
            #expect((22...23).contains(cal.component(.hour, from: l.heure)))
        }
    }

    @Test("Corrections : glycémie notée, au-dessus de 240 (185 le soir), jamais la nuit")
    func corrections() {
        let corrections = jeu.injections.filter { $0.type == .rapideCorrection }
        #expect(!corrections.isEmpty)
        #expect(corrections.allSatisfy {
            let soir = (21..<23).contains(cal.component(.hour, from: $0.heure))
            return ($0.glycemie ?? 0) > (soir ? 185 : 240)
        })
        #expect(corrections.allSatisfy { (7...23).contains(cal.component(.hour, from: $0.heure)) })
        // Des corrections du coucher, pour l'analyse « Hypos au coucher ».
        #expect(corrections.filter { (21..<23).contains(cal.component(.hour, from: $0.heure)) }.count >= 4)
    }

    @Test("Prises de glucides pendant les séances longues ou intenses, intention préventive")
    func prisesSport() {
        let preventives = jeu.resucrages.filter { $0.intention != .correctifHypo }
        #expect(preventives.contains { $0.intention == .preventifMaintien })
        #expect(preventives.contains { $0.intention == .preventifAntiChute })
        #expect(preventives.allSatisfy { p in
            jeu.seances.contains { p.date >= $0.debut.addingTimeInterval(-15 * 60) && p.date <= $0.fin }
        })
    }

    @Test("Ratio du dîner changé à J-21 (10 → 12 g/u)")
    func changementRatio() throws {
        let c = try #require(jeu.changements.first)
        #expect(c.parametre == .ratioDiner)
        #expect(c.ancien == 10 && c.nouveau == 12)
        #expect(cal.isDate(c.date, inSameDayAs: jour(JeuDemo.jourChangementRatioDiner)))
    }

    // MARK: Histoire

    @Test("Nuit avec hypo à J-31 : resucrage nocturne et réveil dans le sommeil")
    func nuitAvecHypo() throws {
        let debut = jour(JeuDemo.jourNuitHypo).addingTimeInterval(23 * 3600)
        let fin = debut.addingTimeInterval(8 * 3600)
        let resucrage = try #require(jeu.resucrages.first { $0.date > debut && $0.date < fin })
        #expect(resucrage.glycemie < 70)
        #expect(jeu.sommeil.contains { $0.stade == .awake && $0.debut <= resucrage.date && $0.fin >= resucrage.date })
    }

    @Test("Pizza récurrente : au moins 4 fois sur 45 jours, la dernière hors cible")
    func pizzaRecurrente() throws {
        let pizzas = jeu.repas.filter { $0.aliments.first?.nom == GenerateurDemo.pizza.nom && $0.heure >= jour(-45) }
        #expect(pizzas.count >= 4)
        let derniere = try #require(pizzas.last)
        let pic = glycemies(de: derniere.heure, a: derniere.heure.addingTimeInterval(4 * 3600)).max() ?? 0
        #expect(pic > 220, "pic \(pic)")
        // Même composition (égalité stricte des noms, glucides à ±15 g).
        let glucides = pizzas.map(\.glucides)
        #expect((glucides.max()! - glucides.min()!) <= 15)
    }

    @Test("Repas rapprochés : des desserts pris moins d'une heure après le déjeuner")
    func repasRapproches() {
        let paires = zip(jeu.repas, jeu.repas.dropFirst()).filter { $1.heure.timeIntervalSince($0.heure) < 3600 }
        #expect(paires.count >= 5)
    }

    @Test("Séances : FC présente, plus nombreuses en charge haute, assez pour une FC max observée")
    func seances() {
        #expect(jeu.seances.count >= 10)
        #expect(jeu.seances.allSatisfy { $0.fcMoyenne > 90 && $0.fcPic > $0.fcMoyenne && $0.fcPic < 200 })
        let haute = jeu.seances.filter { $0.debut >= jour(JeuDemo.debutChargeHaute) }.count
        let normale = jeu.seances.count - haute
        let parSemaineHaute = Double(haute) / 5
        let parSemaineNormale = Double(normale) / 8
        #expect(parSemaineHaute > parSemaineNormale * 1.5)
        #expect(Set(jeu.seances.map(\.workoutUUID)).count == jeu.seances.count)
    }

    @Test("Marche : bouts soutenus (≥ 100 pas/min, ≥ 10 min)")
    func marche() {
        #expect(jeu.marches.count > 150)
        #expect(jeu.marches.allSatisfy { $0.cadence >= 100 && $0.fin.timeIntervalSince($0.debut) >= 600 })
    }

    @Test("Sommeil : chaque nuit a ses stades, sans chevauchement")
    func sommeil() {
        let stades = jeu.sommeil
        #expect(zip(stades, stades.dropFirst()).allSatisfy { $0.fin <= $1.debut })
        for j in -80 ... -1 {
            let nuit = stades.filter { $0.debut >= jour(j).addingTimeInterval(22 * 3600) && $0.debut < jour(j + 1).addingTimeInterval(10 * 3600) }
            #expect(nuit.contains { $0.stade == .deep }, "J\(j)")
            let duree = nuit.reduce(0) { $0 + $1.fin.timeIntervalSince($1.debut) } / 3600
            #expect(duree > 6 && duree < 11, "J\(j) : \(duree) h")
        }
    }

    // MARK: Hub

    @Test("Insertion dans le hub : tout arrive, profil valide")
    func insertionHub() throws {
        let container = try ModelContainer(
            for: GlucoseReading.self, Injection.self, Repas.self, Aliment.self,
                 ActiviteSportive.self, EtatDeclare.self, Medicament.self, PeriodePause.self,
                 Resucrage.self, ProfilUtilisateur.self, ChangementParametre.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let contexte = container.mainContext
        jeu.inserer(dans: contexte)
        #expect(try contexte.fetchCount(FetchDescriptor<GlucoseReading>()) == jeu.glycemies.count)
        #expect(try contexte.fetchCount(FetchDescriptor<Repas>()) == jeu.repas.count)
        #expect(try contexte.fetchCount(FetchDescriptor<Injection>()) == jeu.injections.count)
        #expect(try contexte.fetchCount(FetchDescriptor<Resucrage>()) == jeu.resucrages.count)
        #expect(try contexte.fetchCount(FetchDescriptor<ActiviteSportive>()) == jeu.seances.count)
        let profils = try contexte.fetch(FetchDescriptor<ProfilUtilisateur>())
        #expect(profils.count == 1)
        #expect(profils.first?.estValide == true)
        #expect(profils.first?.prenom == JeuDemo.prenom)
    }
}
