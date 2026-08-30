//
//  CalculAnalyseBasale.swift
//  diaviz
//
//  Created by Alexandre on 27/06/2026.
//

import Foundation

// MARK: - Entrées (value types, découplés de SwiftData)

/// Faits bruts du hub nécessaires à l'analyse B1, mappés en value types par
/// le service hub pour que le calculateur reste **pur** (aucune dépendance
/// SwiftData / MainActor). Tout est horodaté absolu.
struct EntreesBasale: Sendable {
    /// Mesures CGM `(date, mg/dL)`, ordre quelconque.
    let lectures: [(date: Date, valeur: Int)]
    /// Injections de lente `(heure, dose u)` — ancre des nuits + historique dose.
    let lentes: [(heure: Date, dose: Double)]
    /// Injections rapides `(heure, dose, correction)` — IOB + bolus de correction.
    let rapides: [(heure: Date, dose: Double, correction: Bool)]
    /// Repas `(heure, glucides g)` — exclusion repas tardif. **Sans** les
    /// resucrages, qui vivent dans `resucrages` (fait de hub distinct).
    let repas: [(heure: Date, glucides: Int)]
    /// Resucrages `(heure, glucides g, intention)` — prises de glucides pour
    /// traiter ou prévenir une hypo. Fait de hub à part entière depuis la
    /// section « Resucrage » du Journal ; inclut aussi les repas dont tous
    /// les aliments portent le badge `resucrage`.
    ///
    /// L'intention pèse différemment selon la question posée (option 2, doc
    /// Eraser B1) : toutes intentions confondues pour l'exclusion de zone et
    /// le libellé « resucré vs spontané » (des glucides restent des
    /// glucides), mais seul `correctifHypo` peut produire une **rechute** —
    /// une rechute signifie « ma correction a échoué », et on ne peut
    /// échouer qu'une correction.
    let resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)]
    /// Activités sportives `(début, durée min)` — exclusion sport tardif.
    let sports: [(debut: Date, dureeMin: Int)]
    /// Périodes de pause `(début, fin?)` — nuits exclues des analyses.
    let pauses: [(debut: Date, fin: Date?)]
}

/// Paramètres de calcul B1. Valeurs cliniques par défaut ; DIA / pic
/// proviennent du profil utilisateur.
///
/// `nonisolated` : le projet a `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// donc tout type est implicitement `@MainActor` sauf marquage explicite —
/// sans ça, l'initialiseur mémorisé (`ConfigBasale()`) serait MainActor et
/// inutilisable depuis le calculateur pur (`nonisolated`).
nonisolated struct ConfigBasale: Sendable {

    /// Défaut du seuil « repas copieux » (g) — exposé pour que l'écran de
    /// réglages affiche la même valeur de repli que le calculateur.
    nonisolated static let seuilRepasCopieuxParDefaut = 100
    /// Bornes proposées par le réglage.
    nonisolated static let plageSeuilRepasCopieux = 40...200

    var seuilHypo: Int = 70
    var seuilSevere: Int = 54
    /// Heure d'horloge (locale) marquant le début du dawn phenomenon — fin de
    /// la zone 3. Fixée à **04:00** pour ne pas capter la montée d'aube (qui
    /// biaiserait vers un faux « ascendante »). V3 : détection auto d'inflexion.
    var dawnHeure: Int = 4
    var fenetreNuits: Int = 14
    /// Dérive (mg/dL) sur la zone 3 en-deçà de laquelle la nuit est jugée
    /// **stable** — aligné sur la règle clinique ±30 mg/dL sur la nuit à jeun
    /// (on classe sur la dérive totale, pas sur une pente ±1 mg/dL/h trop serrée).
    var seuilDeriveStable: Double = 30
    /// Fenêtre (min) entre deux hypos rapprochées : avec repas loggé entre =
    /// **rechute** (resucrage insuffisant) ; sans repas = **hypos en série**
    /// (glycémie qui rase le seuil).
    var fenetreRechuteMin: Double = 60
    /// Fenêtre (min) après le début d'une hypo pendant laquelle un repas
    /// loggé compte comme **resucrage** de cet épisode.
    var fenetreResucrageMin: Double = 20
    /// Durée (min) continue sous le seuil au-delà de laquelle une hypo est
    /// dite **prolongée** (ne remonte pas).
    var dureeProlongeeMin: Double = 30
    /// Nombre de dernières nuits valides qui pilotent le verdict de tendance
    /// (récence — évite qu'une alerte reste figée quand la situation s'améliore).
    var nuitsRecence: Int = 5
    /// Durée d'action insuline rapide (heures) — pour l'IOB résiduel.
    var diaHeures: Double = 4
    /// Temps de pic d'action insuline rapide (minutes).
    var picMinutes: Double = 75
    /// IOB résiduel (u) au-delà duquel la zone est polluée par une rapide.
    /// Évalué **au début de la zone 3**, pas seulement sur les injections qui
    /// y tombent : une correction prise à 23h agit encore à 02h.
    var seuilIOBResiduel: Double = 0.5
    /// Glucides (g) au-delà desquels un repas tardif est jugé copieux.
    /// Réglable dans Profil → Analyse du coucher.
    var seuilRepasCopieux: Int = seuilRepasCopieuxParDefaut
    /// Fenêtre (h) **avant** le début de la zone 3 pendant laquelle un repas
    /// copieux la disqualifie. Un dîner très glucidique s'assimile tard : la
    /// glycémie est belle au coucher puis monte en pleine nuit profonde, ce
    /// que la régression lit à tort comme une basale trop faible.
    var fenetreDigestionH: Double = 5
    /// Durée (min) après la fin d'un épisode hypo pendant laquelle la courbe
    /// est en train de redescendre d'un rebond — pente non basale.
    var fenetreRebondMin: Double = 90
    /// Heure d'horloge à partir de laquelle un repas / sport compte comme « du soir ».
    var heureSoir: Int = 17
}

/// Assembleur **B1 — détection basale inadaptée** : dérivation pure, jamais
/// persistée. Segmente chaque nuit en 5 zones ancrées sur l'heure de lente,
/// calcule la pente de la zone 3 (nuit profonde) par régression linéaire,
/// exclut zone par zone, et produit un `AnalyseBasaleDetail` prêt à afficher.
///
/// Convention « un hub, des dérivations » : ne lit que des faits bruts,
/// recalcule tout à la volée. Formulations factuelles uniquement.
///
/// Doc : Eraser « Diaviz / B1 — Détection basale ».
///
/// `nonisolated` sur le type : le projet a `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, donc sans ce marquage chaque membre serait implicitement
/// MainActor-isolé — inutilisable depuis le point d'entrée `nonisolated`
/// `analyser(...)`. Cascade à toutes les extensions du type ci-dessous.
nonisolated enum CalculAnalyseBasale {

    // MARK: - Classification (dérive → catégorie)

    /// Seuil de dérive par défaut (mg/dL) — partagé avec `basalDistribution`.
    nonisolated static let seuilDeriveStableParDefaut: Double = 30

    /// Classe une nuit à partir de la **dérive** (Δ mg/dL) de sa zone 3, sur la
    /// règle clinique ±30 mg/dL : `|Δ| ≤ seuil` → stable ; `Δ < −seuil` →
    /// descendante (basale trop forte) ; `Δ > +seuil` → ascendante (basale trop
    /// faible).
    nonisolated static func categorie(
        deriveMgDl derive: Double,
        seuil: Double = seuilDeriveStableParDefaut
    ) -> CategorieNuit {
        if derive < -seuil { return .tendanceBasse }
        if derive > seuil { return .tendanceHaute }
        return .stable
    }

    // MARK: - Point d'entrée

    /// Construit l'analyse complète sur la fenêtre de `config.fenetreNuits`
    /// nuits glissantes (jours métaboliques 06h→06h) se terminant à `maintenant`.
    nonisolated static func analyser(
        entrees: EntreesBasale,
        config: ConfigBasale = ConfigBasale(),
        maintenant: Date = Date()
    ) -> AnalyseBasaleDetail {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique(pour: maintenant)

        // Historique de dose + reset : calculés une fois, partagés par toutes les nuits.
        let historique = doseHistory(lentes: entrees.lentes, maintenant: maintenant)
        let doseActuelle = historique.first(where: { $0.isCurrent })?.dose
            ?? entrees.lentes.max(by: { $0.heure < $1.heure })?.dose
            ?? 0
        let changementDose = dernierChangement(historique, maintenant: maintenant)

        // Une nuit par jour métabolique, de la plus ancienne à la plus récente.
        var nuits: [NuitAnalysee] = []
        nuits.reserveCapacity(config.fenetreNuits)
        for decalage in (0..<config.fenetreNuits).reversed() {
            guard let debutJour = cal.date(byAdding: .day, value: -decalage, to: debutCourant) else { continue }
            let estCourante = (decalage == 0)
            nuits.append(
                analyserNuit(
                    debutJourMetabolique: debutJour,
                    estCourante: estCourante,
                    entrees: entrees,
                    config: config,
                    cal: cal
                )
            )
        }

        return assembler(
            nuits: nuits,
            doseActuelle: doseActuelle,
            changementDose: changementDose,
            historique: historique,
            fenetre: config.fenetreNuits,
            config: config,
            cal: cal
        )
    }

    // MARK: - Résultat intermédiaire par nuit

    /// Synthèse interne d'une nuit avant agrégation. Porte l'état timeline, la
    /// donnée graphique (si CGM exploitable) et la pente zone 3 retenue.
    private struct NuitAnalysee {
        let dateNuit: Date            // jour calendaire du soir (clé timeline / sélection)
        let etat: EtatNuit
        let categorie: CategorieNuit? // nil si non valide
        let slopeZone3: Double?       // pente retenue (nil si zone 3 exclue)
        let deriveZone3: Double?      // dérive Δ mg/dL retenue (nil si zone 3 exclue)
        let bilan: BilanHyposNuit     // taxonomie hypos, fenêtre de sommeil complète
        let aHypoProfonde: Bool       // hypo zones 3+4 → trigger « tendance descendante »
        let reveil: Int?              // glycémie au réveil (mg/dL)
        let chart: NightChartData?    // nil si pas de CGM exploitable
    }

    // MARK: - Analyse d'une nuit

    private static func analyserNuit(
        debutJourMetabolique: Date,
        estCourante: Bool,
        entrees: EntreesBasale,
        config: ConfigBasale,
        cal: Calendar
    ) -> NuitAnalysee {
        // Fenêtre du jour métabolique [06h, 06h+24h[. Le soir (~22h) y vit.
        let finJour = debutJourMetabolique.addingTimeInterval(24 * 3600)
        let dateSoir = cal.startOfDay(for: debutJourMetabolique)

        // Lente du soir = dernière lente de la nuit du jour métabolique :
        // prise le soir (≥ heureSoir) **ou après minuit** avant la fin du
        // jour métabolique (ex. 00h30 — c'est toujours la basale de cette
        // nuit, pas celle du lendemain). Sans la branche après-minuit, une
        // lente saisie à 00h01 rendait la nuit « sans lente ».
        let heureFinJour = cal.component(.hour, from: finJour)
        let lenteDuSoir = entrees.lentes
            .filter { l in
                guard l.heure >= debutJourMetabolique && l.heure < finJour else { return false }
                let h = cal.component(.hour, from: l.heure)
                return h >= config.heureSoir || h < heureFinJour
            }
            .max(by: { $0.heure < $1.heure })

        // Bornes du graphique : 21h00 du soir → +10h (07h lendemain). Fixe, pour
        // que toutes les nuits partagent la même grille (moyenne point-à-point).
        let veille = cal.startOfDay(for: dateSoir)
        let debutGrille = cal.date(bySettingHour: 21, minute: 0, second: 0, of: veille) ?? veille
        let finGrille = debutGrille.addingTimeInterval(10 * 3600)

        let cgmFenetre = entrees.lectures
            .filter { $0.date >= debutGrille && $0.date <= finGrille }
            .sorted { $0.date < $1.date }

        // Pas assez de CGM pour tracer / analyser → sans données.
        guard cgmFenetre.count >= 12 else {
            return NuitAnalysee(
                dateNuit: dateSoir,
                etat: estCourante ? .enCours : .sansDonnees,
                categorie: nil, slopeZone3: nil, deriveZone3: nil,
                bilan: BilanHyposNuit(),
                aHypoProfonde: false, reveil: nil, chart: nil
            )
        }

        // Pas de repère lente → nuit non zonable.
        guard let lente = lenteDuSoir else {
            let chart = construireChart(
                dateNuit: dateSoir, lente: nil, doseLente: 0,
                debutGrille: debutGrille, cgm: cgmFenetre,
                zones: [], events: [], statut: .excluded, slopeZone3: nil,
                bilan: BilanHyposNuit(),
                motif: RaisonExclusion.pasDeLente.rawValue
            )
            return NuitAnalysee(
                dateNuit: dateSoir,
                etat: estCourante ? .enCours : .exclue(raison: .pasDeLente),
                categorie: nil, slopeZone3: nil, deriveZone3: nil,
                bilan: BilanHyposNuit(),
                aHypoProfonde: false, reveil: cgmFenetre.last?.valeur, chart: chart
            )
        }

        let L = lente.heure
        let dawn = prochainDawn(apres: L, heure: config.dawnHeure, cal: cal)
        let z1 = L.addingTimeInterval(-3 * 3600)...L
        let z2 = L...L.addingTimeInterval(2 * 3600)
        let finZ3 = max(z2.upperBound, dawn)         // garde z3 non vide même si lente tardive
        let z3 = z2.upperBound...finZ3
        let reveilDate = min(finGrille, finZ3.addingTimeInterval(2 * 3600))
        let z4 = finZ3...max(finZ3, reveilDate)

        // Pause active sur la nuit → exclusion immédiate (donnée enregistrée mais hors analyse).
        let enPause = entrees.pauses.contains { p in
            let chevauche = (p.fin ?? finGrille) >= debutGrille && p.debut <= finGrille
            return chevauche && p.debut <= dawn && (p.fin ?? finGrille) >= L
        }

        // Hypos sur la fenêtre de sommeil **complète** (endormissement → fin de
        // nuit, zone 4 incluse : une hypo à 4h45 reste une hypo, seule la
        // *dérive* de la zone dawn est exclue du calcul) — source unique.
        let fenetreSommeil = z2.lowerBound...z4.upperBound
        let episodes = episodesHypoDetail(
            cgmFenetre.filter { fenetreSommeil.contains($0.date) }, seuil: config.seuilHypo
        )
        let bilan = bilanHypos(
            episodes: episodes, resucrages: entrees.resucrages,
            finEndormissement: z2.upperBound, config: config
        )
        let aHypoZone3 = episodes.contains { z3.contains($0.bas) }
        let aHypoProfonde = bilan.episodesProfonds > 0

        // Évaluation de la zone 3 (cœur du calcul) — classification sur la dérive.
        let pointsZ3 = cgmFenetre.filter { z3.contains($0.date) }
        let evalZ3 = evaluerZone3(
            points: pointsZ3, plage: z3, enPause: enPause,
            rapides: entrees.rapides, repas: entrees.repas,
            resucrages: entrees.resucrages, episodes: episodes, config: config
        )

        // Évaluation de la zone 2 (pour la répartition + statut partiel).
        let pointsZ2 = cgmFenetre.filter { z2.contains($0.date) }
        let evalZ2 = evaluerZoneSecondaire(points: pointsZ2, config: config)

        // Événements + structures graphiques.
        let events = construireEvents(
            lente: lente, cgm: cgmFenetre, plage: debutGrille...finGrille,
            rapides: entrees.rapides, repas: entrees.repas,
            resucrages: entrees.resucrages, config: config
        )
        let zonesData = construireZonesData(
            z1: z1, z2: z2, z3: z3, z4: z4,
            cgm: cgmFenetre, evalZ2: evalZ2, evalZ3: evalZ3,
            aHypoZone3: aHypoZone3, events: events
        )

        // État de la nuit (pilote la timeline + le verdict).
        let etat: EtatNuit
        let categorie: CategorieNuit?
        let statut: NightStatus
        if estCourante {
            etat = .enCours; categorie = nil
            statut = evalZ3.analysee ? .valid : .excluded
        } else if let cat = evalZ3.categorie {
            // Hypo profonde (zones 3+4) → la nuit ne compte jamais « stable » :
            // une courbe plate malgré une hypo doit sa stabilité au resucrage
            // (ou à la contre-régulation), pas à la basale. Le danger bas prime.
            let catEffective: CategorieNuit = aHypoProfonde ? .tendanceBasse : cat
            etat = .valide(categorie: catEffective); categorie = catEffective
            statut = evalZ2.analysee ? .valid : .partiallyValid
        } else {
            etat = .exclue(raison: evalZ3.raison ?? .cgmIncomplet); categorie = nil
            statut = .excluded
        }

        let reveil = glycemieReveil(cgmFenetre, avant: reveilDate) ?? cgmFenetre.last?.valeur
        let chart = construireChart(
            dateNuit: dateSoir, lente: lente, doseLente: lente.dose,
            debutGrille: debutGrille, cgm: cgmFenetre,
            zones: zonesData, events: events, statut: statut,
            slopeZone3: evalZ3.slope, bilan: bilan,
            motif: evalZ3.categorie == nil ? (evalZ3.raison?.rawValue) : nil
        )

        return NuitAnalysee(
            dateNuit: dateSoir, etat: etat, categorie: categorie,
            slopeZone3: evalZ3.categorie != nil ? evalZ3.slope : nil,
            deriveZone3: evalZ3.categorie != nil ? evalZ3.derive : nil,
            bilan: bilan, aHypoProfonde: aHypoProfonde,
            reveil: reveil, chart: chart
        )
    }

    // MARK: - Évaluation zone 3 (pente basale)

    private struct EvalZone3 {
        let analysee: Bool
        let categorie: CategorieNuit?   // nil si non analysée
        let slope: Double?              // pente mg/dL/h (affichage)
        let derive: Double?             // dérive Δ mg/dL (unité de décision)
        let raison: RaisonExclusion?
    }

    private static func evaluerZone3(
        points: [(date: Date, valeur: Int)],
        plage: ClosedRange<Date>,
        enPause: Bool,
        rapides: [(heure: Date, dose: Double, correction: Bool)],
        repas: [(heure: Date, glucides: Int)],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)],
        episodes: [EpisodeHypo],
        config: ConfigBasale
    ) -> EvalZone3 {
        func exclue(_ raison: RaisonExclusion) -> EvalZone3 {
            EvalZone3(analysee: false, categorie: nil, slope: nil, derive: nil, raison: raison)
        }

        // Critères d'exclusion (par ordre de priorité de message).
        if enPause { return exclue(.modePause) }
        let dureeH = plage.upperBound.timeIntervalSince(plage.lowerBound) / 3600
        if dureeH < 1.5 { return exclue(.dureeInsuffisante) }
        let attendus = max(1, Int(dureeH * 12))   // 12 points/h à 5 min
        if Double(points.count) / Double(attendus) < 0.80 { return exclue(.cgmIncomplet) }
        if rapides.contains(where: { $0.correction && plage.contains($0.heure) }) {
            return exclue(.bolusCorrection)
        }
        // IOB résiduel au **début** de la zone : une rapide antérieure dont la
        // queue d'action traverse la fenêtre fait descendre la glycémie sans
        // que la basale y soit pour quelque chose. Le test « injection dans la
        // zone » ci-dessus ne l'attrapait pas.
        let iobDebut = IOBCalculateur.iob(
            a: plage.lowerBound,
            injections: rapides.filter { $0.heure <= plage.lowerBound }
                .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) },
            diaHeures: config.diaHeures,
            picMinutes: config.picMinutes
        )
        if iobDebut > config.seuilIOBResiduel { return exclue(.iobResiduel) }
        // Resucrage dans la zone → rebond glucidique qui fausse la pente,
        // quelle que soit sa taille (contrairement au repas copieux ci-dessous,
        // qui vise un repas ordinaire tardif).
        if resucrageDans(plage, episodes: episodes, resucrages: resucrages, config: config) {
            return exclue(.resucrage)
        }
        // Repas copieux dans la zone **ou dans les heures qui la précèdent** :
        // un dîner très glucidique s'assimile tard, la glycémie reste belle au
        // coucher puis monte en pleine nuit profonde. La régression y lisait
        // une basale trop faible ; c'est de la digestion.
        let debutDigestion = plage.lowerBound.addingTimeInterval(-config.fenetreDigestionH * 3600)
        if repas.contains(where: {
            $0.heure >= debutDigestion && $0.heure <= plage.upperBound
                && $0.glucides > config.seuilRepasCopieux
        }) {
            return exclue(.repasCopieux)
        }
        // Retombée d'un rebond post-hypo : après une remontée (resucrage ou
        // contre-régulation), la glycémie redescend de son dépassement. Pente
        // réelle, mais qui ne dit rien de la basale.
        if episodes.contains(where: {
            let finRebond = $0.fin.addingTimeInterval(config.fenetreRebondMin * 60)
            return $0.fin <= plage.lowerBound && finRebond > plage.lowerBound
        }) {
            return exclue(.rebondPostHypo)
        }
        if coefficientVariation(points.map(\.valeur)) > 0.36 { return exclue(.chaotique) }

        guard let slope = penteRegression(points, depuis: plage.lowerBound) else {
            return exclue(.cgmIncomplet)
        }
        // Classification sur la **dérive totale** (pente × durée), pas sur la pente.
        let derive = slope * dureeH
        let categorie = categorie(deriveMgDl: derive, seuil: config.seuilDeriveStable)
        return EvalZone3(analysee: true, categorie: categorie, slope: slope, derive: derive, raison: nil)
    }

    private struct EvalZoneSecondaire {
        let analysee: Bool
        let slope: Double?
    }

    /// Zone 2 (endormissement) : on ne calcule que sa pente + son statut
    /// (analysée sauf si chaotique), pour alimenter la répartition zones 2+3.
    private static func evaluerZoneSecondaire(
        points: [(date: Date, valeur: Int)],
        config: ConfigBasale
    ) -> EvalZoneSecondaire {
        guard points.count >= 3 else { return EvalZoneSecondaire(analysee: false, slope: nil) }
        let chaotique = coefficientVariation(points.map(\.valeur)) > 0.36
        let slope = penteRegression(points, depuis: points.first!.date)
        return EvalZoneSecondaire(analysee: !chaotique, slope: slope)
    }

    // MARK: - Assemblage final

    private static func assembler(
        nuits: [NuitAnalysee],
        doseActuelle: Double,
        changementDose: Date?,
        historique: [DoseChange],
        fenetre: Int,
        config: ConfigBasale,
        cal: Calendar
    ) -> AnalyseBasaleDetail {

        // Fenêtre comparable = nuits depuis le dernier changement de dose.
        func avantChangement(_ date: Date) -> Bool {
            guard let chg = changementDose else { return false }
            return cal.startOfDay(for: date) < cal.startOfDay(for: chg)
        }

        // Nuits valides (post-changement, hors nuit en cours), de l'ancienne à
        // la plus récente — `nuits` est déjà ordonné ainsi.
        let valides = nuits.filter {
            if case .valide = $0.etat { return !avantChangement($0.dateNuit) }
            return false
        }
        // Récence : le verdict + la pente moyenne portent sur les K dernières
        // nuits valides (pas toute la fenêtre → évite l'alerte figée).
        let recentes = Array(valides.suffix(config.nuitsRecence))
        let pentesRecentes = recentes.compactMap(\.slopeZone3)
        let penteMoyenne = pentesRecentes.isEmpty ? 0 : pentesRecentes.reduce(0, +) / Double(pentesRecentes.count)
        let derivesRecentes = recentes.compactMap(\.deriveZone3)
        let deriveMoyenne = derivesRecentes.isEmpty ? 0 : derivesRecentes.reduce(0, +) / Double(derivesRecentes.count)

        let stables = valides.filter { $0.categorie == .stable }.count
        let basses = valides.filter { $0.categorie == .tendanceBasse }.count
        let hautes = valides.filter { $0.categorie == .tendanceHaute }.count
        let exclues = nuits.filter {
            if case .exclue = $0.etat { return !avantChangement($0.dateNuit) }
            return false
        }.count

        // Hypos / resucrages : source unique (compteurs par nuit), sommés sur
        // toute la fenêtre comparable (hors nuit en cours).
        let fenetreComparable = nuits.filter { n in
            if case .enCours = n.etat { return false }
            return !avantChangement(n.dateNuit)
        }
        let hypos = fenetreComparable.reduce(0) { $0 + $1.bilan.episodes }
        let resucrages = fenetreComparable.reduce(0) { $0 + $1.bilan.rechutes }
        let reveils = valides.compactMap(\.reveil)
        let reveilMoyen = reveils.isEmpty ? 0 : reveils.reduce(0, +) / reveils.count

        let (verdict, enAmelioration) = deduireVerdict(valides: valides, recentes: recentes)

        // Données graphiques : nuits exploitables (CGM présent), plus récente
        // d'abord — décorées avec leur place dans le verdict (catégorie
        // effective + appartenance à la fenêtre de récence) pour le pied de
        // la carte « Verdict de la nuit ».
        let datesRetenues = Set(recentes.map(\.dateNuit))
        let nightData = nuits.compactMap { n -> NightChartData? in
            guard var chart = n.chart else { return nil }
            chart.categorieVerdict = n.categorie
            chart.retenueDansVerdict = datesRetenues.contains(n.dateNuit)
            return chart
        }.sorted { $0.date > $1.date }

        // Timeline : ancienne → récente, avec drapeau pré-changement.
        let timeline = nuits.map {
            NuitTimeline(date: $0.dateNuit, etat: $0.etat,
                         avantChangementDose: avantChangement($0.dateNuit))
        }

        var detail = AnalyseBasaleDetail(
            verdict: verdict,
            doseActuelle: doseActuelle,
            changementDoseRecent: changementDose,
            penteMoyenne: penteMoyenne,
            nuitsAnalysees: valides.count,
            nuitsExclues: exclues,
            nuitsStables: stables,
            nuitsTendanceBasse: basses,
            nuitsTendanceHaute: hautes,
            hyposNocturnes: hypos,
            resucragesAvecRechute: resucrages,
            glycemieMoyenneReveil: reveilMoyen,
            courbes: [],                 // champ legacy non consommé par les vues
            tendanceMoyenne: [],         // idem
            nightChartData: nightData,
            timeline: timeline,
            resumeIA: nil                // narration IA différée (V1)
        )
        detail.doseHistoriqueReel = historique
        detail.enAmelioration = enAmelioration
        detail.deriveMoyenne = deriveMoyenne
        // Hypos sur les seules nuits retenues : même fenêtre que la dérive et
        // que « en amélioration », pour que la carte verdict ne juxtapose plus
        // deux échelles de temps sans le dire.
        detail.hyposNuitsRetenues = recentes.reduce(0) { $0 + $1.bilan.episodes }
        return detail
    }

    /// Verdict B1 + drapeau « en amélioration ». Formulations factuelles.
    /// Le verdict de tendance porte sur les **nuits récentes** (`recentes`) ;
    /// « en amélioration » se lève quand la fenêtre globale était à revoir mais
    /// que le récent est redevenu stable (typiquement une reprise de sport).
    private static func deduireVerdict(
        valides: [NuitAnalysee], recentes: [NuitAnalysee]
    ) -> (VerdictBasale, enAmelioration: Bool) {
        guard valides.count >= 3 else { return (.donneesInsuffisantes, false) }

        // Signal descendant immédiat : hypo zone 3 récente ou resucrage avec rechute.
        if recentes.contains(where: { $0.aHypoProfonde || $0.bilan.rechutes > 0 }) {
            return (.tropHaute, false)
        }

        func compte(_ cat: CategorieNuit, dans nuits: [NuitAnalysee]) -> Int {
            nuits.filter { $0.categorie == cat }.count
        }
        let aRec = compte(.tendanceHaute, dans: recentes)
        let dRec = compte(.tendanceBasse, dans: recentes)

        let verdictRecent: VerdictBasale
        if aRec >= 3 && aRec >= dRec { verdictRecent = .tropBasse }
        else if dRec >= 3 && dRec >= aRec { verdictRecent = .tropHaute }
        else { verdictRecent = .adaptee }

        // « En amélioration » : la fenêtre globale penchait « à revoir » mais le
        // récent est revenu à stable.
        let fenetreARevoir = compte(.tendanceHaute, dans: valides) >= 3
            || compte(.tendanceBasse, dans: valides) >= 3
        let enAmelioration = fenetreARevoir && verdictRecent == .adaptee

        return (verdictRecent, enAmelioration)
    }

    // MARK: - Historique de dose (détection + reset)

    /// Regroupe les lentes en paliers de dose consécutifs. Dose courante en
    /// tête (`endDate == nil`). Une nouvelle entrée naît à chaque changement de dose.
    private static func doseHistory(
        lentes: [(heure: Date, dose: Double)],
        maintenant: Date
    ) -> [DoseChange] {
        let triees = lentes.sorted { $0.heure < $1.heure }
        guard !triees.isEmpty else { return [] }

        // Paliers : (dose, début).
        var paliers: [(dose: Double, debut: Date)] = []
        for l in triees {
            if let dernier = paliers.last, dernier.dose == l.dose { continue }
            paliers.append((dose: l.dose, debut: l.heure))
        }

        // Construit les DoseChange du plus récent au plus ancien.
        var resultat: [DoseChange] = []
        for (i, palier) in paliers.enumerated().reversed() {
            let fin: Date? = (i == paliers.count - 1) ? nil : paliers[i + 1].debut
            resultat.append(DoseChange(dose: palier.dose, startDate: palier.debut, endDate: fin))
        }
        return resultat
    }

    /// Date du dernier changement de dose s'il est récent (< 30 j) et précédé
    /// d'au moins un palier antérieur ; sinon `nil` (pas de reset à signaler).
    private static func dernierChangement(_ historique: [DoseChange], maintenant: Date) -> Date? {
        guard historique.count >= 2, let courant = historique.first(where: { $0.isCurrent }) else { return nil }
        let jours = maintenant.timeIntervalSince(courant.startDate) / 86_400
        return jours <= 30 ? courant.startDate : nil
    }

    // MARK: - Outils numériques

    /// Pente par régression linéaire moindres carrés. `x` en heures depuis
    /// `depuis`, `y` en mg/dL → mg/dL/h. `nil` si moins de 2 points ou plat.
    private static func penteRegression(
        _ points: [(date: Date, valeur: Int)],
        depuis origine: Date
    ) -> Double? {
        guard points.count >= 2 else { return nil }
        let n = Double(points.count)
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for p in points {
            let x = p.date.timeIntervalSince(origine) / 3600
            let y = Double(p.valeur)
            sx += x; sy += y; sxx += x * x; sxy += x * y
        }
        let denom = n * sxx - sx * sx
        guard abs(denom) > 1e-9 else { return nil }
        return (n * sxy - sx * sy) / denom
    }

    /// Coefficient de variation (écart-type / moyenne). 0 si moins de 2 points.
    private static func coefficientVariation(_ valeurs: [Int]) -> Double {
        guard valeurs.count >= 2 else { return 0 }
        let xs = valeurs.map(Double.init)
        let moyenne = xs.reduce(0, +) / Double(xs.count)
        guard moyenne > 0 else { return 0 }
        let variance = xs.map { pow($0 - moyenne, 2) }.reduce(0, +) / Double(xs.count)
        return sqrt(variance) / moyenne
    }

    private static func prochainDawn(apres date: Date, heure: Int, cal: Calendar) -> Date {
        var d = cal.date(bySettingHour: heure, minute: 0, second: 0, of: date) ?? date
        if d <= date { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }
}

#if DEBUG
extension CalculAnalyseBasale {

    /// Jeu de données **synthétique** (déterministe) exerçant le vrai pipeline
    /// dans les previews — 14 nuits de CGM à pas 5 min avec une basale
    /// légèrement trop forte (descente nocturne ~ −1,3 mg/dL/h), lente 18u à
    /// 22h30. Permet de valider l'algo réel sans device ni HealthKit.
    static func apercu(maintenant: Date = Date()) -> AnalyseBasaleDetail {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique(pour: maintenant)
        var lectures: [(date: Date, valeur: Int)] = []
        var lentes: [(heure: Date, dose: Double)] = []

        for decalage in 1...14 {
            guard let jour = cal.date(byAdding: .day, value: -decalage, to: debutCourant) else { continue }
            let veille = cal.startOfDay(for: jour)
            let debut = cal.date(bySettingHour: 21, minute: 0, second: 0, of: veille) ?? veille
            let lente = cal.date(bySettingHour: 22, minute: 30, second: 0, of: veille) ?? debut
            lentes.append((heure: lente, dose: 18))

            // 121 points de 21h à 07h. Descente marquée en zone 3 (dérive
            // ~ −40 mg/dL > seuil) → nuit « descendante » = basale trop forte.
            for i in 0..<121 {
                let t = debut.addingTimeInterval(Double(i) * 300)
                let h = Double(i) / 12.0                          // heures depuis 21h
                let descente = -12.0 * max(0, h - 3.5)            // commence ~00h30
                let bruit = 4.0 * sin(Double(i) * 0.6 + Double(decalage))
                let valeur = Int((132 + descente + bruit).rounded())
                lectures.append((date: t, valeur: max(55, min(260, valeur))))
            }
        }

        let entrees = EntreesBasale(
            lectures: lectures, lentes: lentes, rapides: [],
            repas: [], resucrages: [], sports: [], pauses: []
        )
        return analyser(entrees: entrees, maintenant: maintenant)
    }
}
#endif

// MARK: - Construction des structures graphiques (NightChartData)

// `nonisolated` explicite : une extension ne dérive pas l'isolation de son
// type étendu (contrairement aux membres déclarés dans le type lui-même) —
// sans ce marquage, ces helpers redeviendraient MainActor-isolés malgré
// `nonisolated enum CalculAnalyseBasale` ci-dessus.
private nonisolated extension CalculAnalyseBasale {

    /// Nombre de points de la grille d'affichage — 121 échantillons à pas 5 min
    /// sur 10h (21h→07h). Identique pour **toutes** les nuits : c'est ce qui
    /// permet la moyenne point-à-point de la vue agrégée sans crash.
    static let nbPointsGrille = 121

    /// Assemble la `NightChartData` d'une nuit. Les glycémies sont
    /// **rééchantillonnées** sur la grille fixe ; les events / zones gardent
    /// leurs temps réels.
    static func construireChart(
        dateNuit: Date,
        lente: (heure: Date, dose: Double)?,
        doseLente: Double,
        debutGrille: Date,
        cgm: [(date: Date, valeur: Int)],
        zones: [ZoneData],
        events: [NightEvent],
        statut: NightStatus,
        slopeZone3: Double?,
        bilan: BilanHyposNuit,
        motif: String?
    ) -> NightChartData {
        let glucose = echantillonnerGrille(cgm: cgm, debut: debutGrille)
        let basaleTime = lente?.heure ?? debutGrille
        let depart = cgm.min(by: { abs($0.date.timeIntervalSince(basaleTime)) < abs($1.date.timeIntervalSince(basaleTime)) })?.valeur
        let reveil = glycemieReveil(cgm, avant: cgm.last?.date ?? debutGrille) ?? cgm.last?.valeur ?? depart ?? 0

        var chart = NightChartData(
            date: dateNuit,
            glucoseValues: glucose,
            basaleTime: basaleTime,
            basaleDose: doseLente,
            startGlucose: Double(depart ?? reveil),
            wakeUpGlucose: Double(reveil),
            zones: zones,
            events: events,
            overallStatus: statut,
            slopeZone3: slopeZone3,
            motifExclusion: motif
        )
        chart.hypoCount = bilan.episodes
        chart.rechuteCount = bilan.rechutes
        chart.bilanHypos = bilan
        return chart
    }

    /// Rééchantillonne les mesures réelles sur la grille fixe (interpolation
    /// linéaire, clamp aux bords). Garantit `nbPointsGrille` points alignés sur
    /// la même horloge pour chaque nuit.
    static func echantillonnerGrille(
        cgm: [(date: Date, valeur: Int)],
        debut: Date
    ) -> [GlucosePoint] {
        guard let premier = cgm.first, let dernier = cgm.last else { return [] }
        var points: [GlucosePoint] = []
        points.reserveCapacity(nbPointsGrille)
        for i in 0..<nbPointsGrille {
            let t = debut.addingTimeInterval(Double(i) * 300)
            let valeur: Double
            if t <= premier.date {
                valeur = Double(premier.valeur)
            } else if t >= dernier.date {
                valeur = Double(dernier.valeur)
            } else {
                valeur = interpoler(cgm, a: t)
            }
            points.append(GlucosePoint(time: t, value: valeur))
        }
        return points
    }

    /// Interpolation linéaire entre les deux mesures encadrant `t`.
    static func interpoler(_ cgm: [(date: Date, valeur: Int)], a t: Date) -> Double {
        var precedent = cgm[0]
        for p in cgm {
            if p.date >= t {
                let dt = p.date.timeIntervalSince(precedent.date)
                guard dt > 0 else { return Double(p.valeur) }
                let frac = t.timeIntervalSince(precedent.date) / dt
                return Double(precedent.valeur) + frac * Double(p.valeur - precedent.valeur)
            }
            precedent = p
        }
        return Double(precedent.valeur)
    }

    /// Construit la liste plate des événements de la nuit : lente, rapides,
    /// hypos, resucrages, repas.
    static func construireEvents(
        lente: (heure: Date, dose: Double)?,
        cgm: [(date: Date, valeur: Int)],
        plage: ClosedRange<Date>,
        rapides: [(heure: Date, dose: Double, correction: Bool)],
        repas: [(heure: Date, glucides: Int)],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)] = [],
        config: ConfigBasale
    ) -> [NightEvent] {
        var events: [NightEvent] = []

        if let lente {
            events.append(NightEvent(type: .lente, time: lente.heure, value: 0,
                                     detail: "\(doseFmt(lente.dose))u à \(heureFr(lente.heure))"))
        }
        for r in rapides where plage.contains(r.heure) {
            let v = valeurProche(cgm, a: r.heure)
            events.append(NightEvent(type: .rapide, time: r.heure, value: v,
                                     detail: "\(doseFmt(r.dose))u à \(heureFr(r.heure))"))
        }

        // Hypos : un point par épisode contigu sous le seuil (le minimum local).
        for h in episodesHypo(cgm, seuil: config.seuilHypo) {
            events.append(NightEvent(type: .hypo, time: h.date, value: Double(h.valeur),
                                     detail: "\(h.valeur) mg/dL à \(heureFr(h.date))"))
        }

        // Resucrages — pill dédiée, distincte du repas nocturne : ce sont
        // les glucides pris pour traiter ou prévenir une hypo.
        for r in resucrages where plage.contains(r.heure) {
            events.append(NightEvent(type: .resucrage, time: r.heure,
                                     value: valeurProche(cgm, a: r.heure),
                                     detail: "\(r.glucides)g à \(heureFr(r.heure))"))
        }

        // Repas nocturnes (contexte).
        for m in repas where plage.contains(m.heure) {
            events.append(NightEvent(type: .repas, time: m.heure, value: valeurProche(cgm, a: m.heure),
                                     detail: "\(m.glucides)g à \(heureFr(m.heure))"))
        }
        return events
    }

    /// Les 4 zones avec pente, caractéristique, statut « analysée », et events internes.
    private static func construireZonesData(
        z1: ClosedRange<Date>, z2: ClosedRange<Date>,
        z3: ClosedRange<Date>, z4: ClosedRange<Date>,
        cgm: [(date: Date, valeur: Int)],
        evalZ2: EvalZoneSecondaire, evalZ3: EvalZone3,
        aHypoZone3: Bool,
        events: [NightEvent]
    ) -> [ZoneData] {
        func eventsDans(_ r: ClosedRange<Date>) -> [NightEvent] {
            events.filter { $0.type != .lente && r.contains($0.time) }
        }
        func pts(_ r: ClosedRange<Date>) -> [(date: Date, valeur: Int)] {
            cgm.filter { r.contains($0.date) }
        }

        let z1Pts = pts(z1), z4Pts = pts(z4)
        let z1Slope = penteRegression(z1Pts, depuis: z1.lowerBound)
        let z4Slope = penteRegression(z4Pts, depuis: z4.lowerBound)

        return [
            ZoneData(zone: .preEndormissement, timeRange: z1, slope: z1Slope,
                     characteristic: caracteristique(z1Pts, slope: z1Slope),
                     isAnalyzed: false, exclusionReason: nil, events: eventsDans(z1)),
            ZoneData(zone: .endormissement, timeRange: z2, slope: evalZ2.slope,
                     characteristic: caracteristique(pts(z2), slope: evalZ2.slope),
                     isAnalyzed: evalZ2.analysee,
                     exclusionReason: evalZ2.analysee ? nil : RaisonExclusion.chaotique.rawValue,
                     events: eventsDans(z2)),
            ZoneData(zone: .nuitProfonde, timeRange: z3, slope: evalZ3.slope,
                     characteristic: caracteristique(pts(z3), slope: evalZ3.slope, hypo: aHypoZone3),
                     isAnalyzed: evalZ3.categorie != nil,
                     exclusionReason: evalZ3.categorie != nil ? nil : evalZ3.raison?.rawValue,
                     events: eventsDans(z3)),
            ZoneData(zone: .dawnPhenomenon, timeRange: z4, slope: z4Slope,
                     characteristic: caracteristique(z4Pts, slope: z4Slope),
                     isAnalyzed: false, exclusionReason: nil, events: eventsDans(z4)),
        ]
    }

    // MARK: Petits outils

    /// Un épisode hypo de la zone (bas dans la plage, ou chevauchant) suivi
    /// d'un repas loggé — même fenêtre que le resucrage de `bilanHypos`.
    /// Détecté indépendamment du bilan complet (fenêtre de sommeil entière)
    /// car requis avant lui dans le pipeline, sur la seule plage de la zone.
    static func resucrageDans(
        _ plage: ClosedRange<Date>,
        episodes: [EpisodeHypo],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)],
        config: ConfigBasale
    ) -> Bool {
        // Toutes intentions confondues : des glucides faussent la pente, quelle
        // que soit la raison de la prise (correctif comme préventif).
        episodes.contains { episode in
            guard plage.overlaps(episode.debut...episode.fin) else { return false }
            return resucrages.contains { estDans($0.heure, episode: episode, config: config) }
        }
    }

    /// Points bas des épisodes hypo — pour les pills du graphique.
    static func episodesHypo(_ cgm: [(date: Date, valeur: Int)], seuil: Int) -> [(date: Date, valeur: Int)] {
        episodesHypoDetail(cgm, seuil: seuil).map { (date: $0.bas, valeur: $0.valeur) }
    }

    /// Glycémie au réveil = **médiane** des mesures de la dernière demi-heure
    /// avant `fin` (sinon les 3 derniers points). Plus robuste qu'un point
    /// unique, qui peut être un pic isolé en plein dawn.
    static func glycemieReveil(_ cgm: [(date: Date, valeur: Int)], avant fin: Date) -> Int? {
        let fenetre = cgm.filter { $0.date >= fin.addingTimeInterval(-1800) && $0.date <= fin }
        let echantillon = fenetre.isEmpty ? Array(cgm.suffix(3)) : fenetre
        guard !echantillon.isEmpty else { return nil }
        let triees = echantillon.map(\.valeur).sorted()
        return triees[triees.count / 2]
    }

    static func valeurProche(_ cgm: [(date: Date, valeur: Int)], a t: Date) -> Double {
        guard let p = cgm.min(by: { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) })
        else { return 0 }
        return Double(p.valeur)
    }

    static func caracteristique(_ points: [(date: Date, valeur: Int)], slope: Double?, hypo: Bool = false) -> CurveCharacteristic {
        guard let slope, points.count >= 2 else { return .stable }
        if coefficientVariation(points.map(\.valeur)) > 0.36 { return .chaotic }
        if hypo { return .hypoEvent }
        switch slope {
        case ..<(-3):  return .steepDrop
        case ..<(-1):  return .gradualDrop
        case ...1:     return .stable
        case ...3:     return .gradualRise
        default:       return .steepRise
        }
    }

    static func doseFmt(_ d: Double) -> String {
        d == d.rounded() ? String(format: "%.0f", d) : String(format: "%.1f", d)
    }

    static func heureFr(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%dh%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Taxonomie des hypos (partagée)

/// Découpage en épisodes et taxonomie des hypos — **internes** (et non
/// `private` comme le reste des helpers de ce fichier) parce que B2/B3 les
/// réutilisent via `DetectionRechute` : l'app doit avoir une seule définition
/// de « rechute », pas une par écran.
nonisolated extension CalculAnalyseBasale {

    /// Un épisode hypo contigu : bornes temporelles + point le plus bas.
    typealias EpisodeHypo = (debut: Date, fin: Date, bas: Date, valeur: Int)

    /// Découpe les mesures en épisodes hypo contigus (points < seuil séparés par
    /// un retour au-dessus du seuil).
    static func episodesHypoDetail(_ cgm: [(date: Date, valeur: Int)], seuil: Int) -> [EpisodeHypo] {
        var resultat: [EpisodeHypo] = []
        var courant: [(date: Date, valeur: Int)] = []
        func cloturer() {
            guard let pire = courant.min(by: { $0.valeur < $1.valeur }),
                  let debut = courant.first?.date, let fin = courant.last?.date else { return }
            resultat.append((debut: debut, fin: fin, bas: pire.date, valeur: pire.valeur))
            courant.removeAll()
        }
        for p in cgm {
            if p.valeur < seuil { courant.append(p) }
            else { cloturer() }
        }
        cloturer()
        return resultat
    }

    /// Une prise de glucides traite-t-elle cet épisode ? Fenêtre = durée de
    /// l'épisode, élargie à `fenetreResucrageMin` après son début pour les
    /// hypos très courtes, corrigées avant que le CGM ne remonte.
    static func estDans(
        _ heure: Date, episode: EpisodeHypo, config: ConfigBasale
    ) -> Bool {
        let borne = max(episode.fin, episode.debut.addingTimeInterval(config.fenetreResucrageMin * 60))
        return heure >= episode.debut && heure <= borne
    }

    /// Taxonomie des épisodes hypo d'une nuit (cf. doc `BilanHyposNuit`).
    /// La distinction resucrage / remontée spontanée repose sur le log des
    /// resucrages : aucune prise enregistrée pendant l'épisode → remontée
    /// spontanée par principe (contre-régulation, fin d'action — ou
    /// compression capteur, V2).
    ///
    /// L'intention est pondérée (option 2, doc Eraser B1) : **toutes**
    /// comptent pour « resucré vs spontané » (des glucides ont bien été
    /// pris), mais seul `correctifHypo` peut produire une **rechute** — une
    /// rechute dit « ma correction a échoué », et on ne peut échouer qu'une
    /// correction. Une hypo qui suit un préventif reste une hypo en série.
    static func bilanHypos(
        episodes: [EpisodeHypo],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)],
        finEndormissement: Date,
        config: ConfigBasale
    ) -> BilanHyposNuit {
        var bilan = BilanHyposNuit()
        bilan.episodes = episodes.count
        guard !episodes.isEmpty else { return bilan }

        func estResucre(_ e: EpisodeHypo) -> Bool {
            resucrages.contains { estDans($0.heure, episode: e, config: config) }
        }
        func estCorrige(_ e: EpisodeHypo) -> Bool {
            resucrages.contains {
                $0.intention == .correctifHypo && estDans($0.heure, episode: e, config: config)
            }
        }

        var indicesEnSerie = Set<Int>()
        for (i, e) in episodes.enumerated() {
            if e.bas > finEndormissement { bilan.episodesProfonds += 1 }
            if e.fin.timeIntervalSince(e.debut) >= config.dureeProlongeeMin * 60 {
                bilan.prolongees += 1
            }
            if estResucre(e) { bilan.resucrees += 1 } else { bilan.spontanees += 1 }

            guard i > 0 else { continue }
            let gapMin = e.debut.timeIntervalSince(episodes[i - 1].fin) / 60
            guard gapMin >= 0 && gapMin < config.fenetreRechuteMin else { continue }
            if estCorrige(episodes[i - 1]) {
                // Correction → remontée → nouvelle hypo : rechute.
                bilan.rechutes += 1
            } else {
                // Aucune correction entre les deux : la glycémie rase le
                // seuil — série (y compris après un simple préventif).
                indicesEnSerie.insert(i - 1)
                indicesEnSerie.insert(i)
            }
        }
        bilan.enSerie = indicesEnSerie.count
        return bilan
    }
}
