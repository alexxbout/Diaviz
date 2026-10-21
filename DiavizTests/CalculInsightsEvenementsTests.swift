//
//  CalculInsightsEvenementsTests.swift
//  DiavizTests
//
//  Cartes d'événement de la pile d'accueil : chacune n'existe que pendant sa
//  durée de vie, porte un identifiant stable, et l'ordre de la pile est
//  alerte → événements récents d'abord → cartes d'état.
//

import Foundation
import Testing
@testable import Diaviz

struct CalculInsightsEvenementsTests {

    private let seuils = SeuilsGlycemiques()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func apres(_ heures: Double, de date: Date) -> Date { date.addingTimeInterval(heures * 3600) }

    // MARK: Réponse d'un repas

    private func reponseRepas() -> ReponseGlycemique {
        ReponseGlycemique(
            pointsCgm: [
                PointCgm(secondesDepuisRepas: 0, valeur: 110),
                PointCgm(secondesDepuisRepas: 3600, valeur: 190),
                PointCgm(secondesDepuisRepas: 14_400, valeur: 120),
            ],
            verdict: .moyen, valeurPic: 190, tempsPic: 3600, tempsRetourCible: 10_800
        )
    }

    private func carteRepas(maintenant: Date, id: UUID = UUID()) -> Insight? {
        CalculInsightsEvenements.reponseRepas(
            id: id, heure: t0, reponse: reponseRepas(), seuils: seuils, maintenant: maintenant
        )
    }

    @Test("Réponse d'un repas : rien avant la fin de la fenêtre de 4 h")
    func repasTropTot() {
        #expect(carteRepas(maintenant: apres(3.9, de: t0)) == nil)
    }

    @Test("Réponse d'un repas : visible 24 h après sa disponibilité, puis disparaît")
    func repasDureeDeVie() {
        #expect(carteRepas(maintenant: apres(4, de: t0)) != nil)
        #expect(carteRepas(maintenant: apres(27.9, de: t0)) != nil)
        #expect(carteRepas(maintenant: apres(28.1, de: t0)) == nil)
    }

    @Test("Réponse d'un repas : courbe sans texte, repère à l'instant du repas, pic annoté")
    func repasContenu() throws {
        let id = UUID()
        let carte = try #require(carteRepas(maintenant: apres(5, de: t0), id: id))
        #expect(carte.message.isEmpty)
        #expect(carte.destination == .detailRepas(id))
        guard case .courbe(let courbe) = carte.microVisuel else {
            Issue.record("micro-visuel attendu : courbe")
            return
        }
        #expect(courbe.repere == 0...0)
        #expect(!courbe.repereEstUneBande)
        #expect(courbe.pic?.valeur == 190)
        #expect(courbe.pic?.minutes == 60)
        #expect(courbe.points.count == 3)
    }

    @Test("Identifiant stable pour un même repas, distinct d'un repas à l'autre")
    func repasIdentifiant() throws {
        let id = UUID()
        let a = try #require(carteRepas(maintenant: apres(5, de: t0), id: id))
        let b = try #require(carteRepas(maintenant: apres(9, de: t0), id: id))
        let autre = try #require(carteRepas(maintenant: apres(5, de: t0)))
        #expect(a.id == b.id)
        #expect(a.id != autre.id)
    }

    // MARK: Réponse d'une séance

    private func reponseSeance() -> ReponseGlycemiqueSport {
        ReponseGlycemiqueSport(
            pointsCgm: [
                PointCgmSport(secondesDepuisDebut: -1800, valeur: 150),
                PointCgmSport(secondesDepuisDebut: 0, valeur: 150),
                PointCgmSport(secondesDepuisDebut: 2700, valeur: 95),
            ],
            glycemieDebut: 150, glycemieFin: 95, deltaMgDl: -55
        )
    }

    private func carteSeance(maintenant: Date) -> Insight? {
        CalculInsightsEvenements.reponseSeance(
            id: UUID(), libelleType: "Course", debut: t0, fin: t0.addingTimeInterval(45 * 60),
            dureeMinutes: 45, reponse: reponseSeance(), seuils: seuils, maintenant: maintenant
        )
    }

    @Test("Réponse d'une séance : attend la fin + 30 min + retard capteur (3 h)")
    func seanceDisponibilite() {
        let fin = t0.addingTimeInterval(45 * 60)
        #expect(carteSeance(maintenant: fin.addingTimeInterval(3 * 3600)) == nil)
        #expect(carteSeance(maintenant: fin.addingTimeInterval(3.5 * 3600 + 1)) != nil)
        #expect(carteSeance(maintenant: fin.addingTimeInterval(28 * 3600)) == nil)
    }

    @Test("Réponse d'une séance : la durée de l'effort est une bande")
    func seanceBande() throws {
        let fin = t0.addingTimeInterval(45 * 60)
        let carte = try #require(carteSeance(maintenant: fin.addingTimeInterval(4 * 3600)))
        guard case .courbe(let courbe) = carte.microVisuel else {
            Issue.record("micro-visuel attendu : courbe")
            return
        }
        #expect(courbe.repereEstUneBande)
        #expect(courbe.repere == 0...45)
    }

    // MARK: Activité à importer

    private func candidat(_ fin: Date, id: UUID = UUID()) -> CalculInsightsEvenements.CandidatImport {
        .init(id: id, libelleType: "Course", icone: "figure.run", debut: fin.addingTimeInterval(-3600), fin: fin)
    }

    @Test("Activité à importer : aucune carte sans candidat")
    func importVide() {
        #expect(CalculInsightsEvenements.activitesAImporter([]) == nil)
    }

    @Test("Activité à importer : un nouveau candidat change l'identifiant")
    func importIdentifiant() throws {
        let a = candidat(t0)
        let b = candidat(apres(1, de: t0))
        let seule = try #require(CalculInsightsEvenements.activitesAImporter([a]))
        let deux = try #require(CalculInsightsEvenements.activitesAImporter([a, b]))
        let memeOrdre = try #require(CalculInsightsEvenements.activitesAImporter([b, a]))
        #expect(seule.id != deux.id)
        #expect(deux.id == memeOrdre.id)
        #expect(deux.titre == "2 activités à importer")
        #expect(deux.date == b.fin)
    }

    // MARK: Nouveaux repas à revoir

    @Test("Repas à revoir : seuls les repas des 48 dernières heures comptent")
    func repasARevoirFenetre() throws {
        let maintenant = apres(100, de: t0)
        let carte = try #require(CalculInsightsEvenements.nouveauxRepasARevoir([
            .init(idRepasSource: UUID(), heure: apres(-10, de: maintenant)),
            .init(idRepasSource: UUID(), heure: apres(-47, de: maintenant)),
            .init(idRepasSource: UUID(), heure: apres(-60, de: maintenant)),
        ], maintenant: maintenant))
        guard case .grandNombre(let valeur) = carte.microVisuel else {
            Issue.record("micro-visuel attendu : grand nombre")
            return
        }
        #expect(valeur == "2")
    }

    @Test("Repas à revoir : aucune carte quand tout est plus ancien que 48 h")
    func repasARevoirTropAncien() {
        let maintenant = apres(100, de: t0)
        #expect(CalculInsightsEvenements.nouveauxRepasARevoir([
            .init(idRepasSource: UUID(), heure: apres(-49, de: maintenant)),
        ], maintenant: maintenant) == nil)
    }

    // MARK: Données de ratio

    private func apercu(disponibleIlYA heures: Double?, avecComparaison: Bool = true, maintenant: Date) -> ApercuChangementRatio {
        let changement = apres(-300, de: maintenant)
        return ApercuChangementRatio(
            dateChangement: changement,
            effectifDepuis: 5,
            comparaison: avecComparaison
                ? ComparaisonChangementRatio(
                    dateChangement: changement, avant: nil,
                    apres: StatsPeriodeRatio(doseMoyenne: 5, tauxBon: 0.6, effectif: 5)
                ) : nil,
            dateComparaisonDisponible: heures.map { apres(-$0, de: maintenant) }
        )
    }

    @Test("Données de ratio : visibles 7 jours après la comparaison, puis disparaissent")
    func ratioDureeDeVie() {
        let maintenant = apres(1000, de: t0)
        #expect(CalculInsightsEvenements.donneesRatio([.dejeuner: apercu(disponibleIlYA: 24, maintenant: maintenant)], maintenant: maintenant).count == 1)
        #expect(CalculInsightsEvenements.donneesRatio([.dejeuner: apercu(disponibleIlYA: 24 * 8, maintenant: maintenant)], maintenant: maintenant).isEmpty)
    }

    @Test("Données de ratio : rien tant que la comparaison n'est pas calculable")
    func ratioSansComparaison() {
        let maintenant = apres(1000, de: t0)
        #expect(CalculInsightsEvenements.donneesRatio(
            [.dejeuner: apercu(disponibleIlYA: nil, avecComparaison: false, maintenant: maintenant)], maintenant: maintenant
        ).isEmpty)
    }

    // MARK: Épisode de charge

    private func episode(jours: Int, debut: Date, niveau: NiveauChargeActive? = .haute) -> EpisodeCharge {
        EpisodeCharge(
            debut: debut, dernierJour: debut, enCours: true, niveau: niveau,
            faits: FaitsEpisode(jours: jours, seancesParSemaine: 3, minutesSeancesParSemaine: 120, minutesMarcheParSemaine: 60),
            chargeMoyenne: 1, reglages: [],
            resultats: ResultatsEpisode(tempsDansLaCible: nil, scoreMoyen: nil, resucragesParJour: nil, couvertureCGM: nil)
        )
    }

    private func synthese(enCours: EpisodeCharge?, precedent: EpisodeCharge?) -> SyntheseEpisodesCharge {
        SyntheseEpisodesCharge(enCours: enCours, precedent: precedent, comparables: [], autres: [], etatsActuels: [])
    }

    @Test("Épisode de charge : carte pendant 7 jours, après un épisode précédent")
    func episodeNouveau() {
        let avant = episode(jours: 10, debut: apres(-500, de: t0), niveau: .normale)
        #expect(CalculInsightsEvenements.episodeCharge(synthese(enCours: episode(jours: 7, debut: t0), precedent: avant)) != nil)
        #expect(CalculInsightsEvenements.episodeCharge(synthese(enCours: episode(jours: 8, debut: t0), precedent: avant)) == nil)
    }

    @Test("Épisode de charge : pas de carte pour le tout premier épisode, ni sans référence")
    func episodePremierOuSansReference() {
        let avant = episode(jours: 10, debut: apres(-500, de: t0))
        #expect(CalculInsightsEvenements.episodeCharge(synthese(enCours: episode(jours: 3, debut: t0), precedent: nil)) == nil)
        #expect(CalculInsightsEvenements.episodeCharge(synthese(enCours: episode(jours: 3, debut: t0, niveau: nil), precedent: avant)) == nil)
        #expect(CalculInsightsEvenements.episodeCharge(nil) == nil)
    }

    // MARK: Ordre

    private func carte(_ titre: String, date: Date?) -> Insight {
        Insight(
            id: CalculInsightsEvenements.idDeterministe(titre), categorie: .informatif, titre: titre,
            message: "", microVisuel: .grandNombre(valeur: "1"), lienAnalyse: nil, date: date
        )
    }

    @Test("Ordre : alerte, puis événements du plus récent au plus ancien, puis états")
    func ordre() {
        let ordonne = CalculInsightsEvenements.ordonner(
            alerte: carte("alerte", date: nil),
            evenements: [carte("ancien", date: t0), carte("recent", date: apres(5, de: t0)), carte("milieu", date: apres(2, de: t0))],
            etats: [carte("etat", date: nil)]
        )
        #expect(ordonne.map(\.titre) == ["alerte", "recent", "milieu", "ancien", "etat"])
    }

    @Test("Ordre : sans alerte, les événements ouvrent la pile")
    func ordreSansAlerte() {
        let ordonne = CalculInsightsEvenements.ordonner(
            alerte: nil, evenements: [carte("a", date: t0)], etats: [carte("etat", date: nil)]
        )
        #expect(ordonne.map(\.titre) == ["a", "etat"])
    }
}
