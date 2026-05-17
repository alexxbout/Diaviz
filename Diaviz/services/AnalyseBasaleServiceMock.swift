//
//  AnalyseBasaleServiceMock.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Fenêtre d'analyse

/// Fenêtre clinique standard pour évaluer un changement de dose de
/// basale — 14 nuits. C'est le minimum recommandé par la littérature
/// pour qu'un verdict de tendance soit fiable, sans être si long que
/// les ajustements récents soient masqués par l'historique.
///
/// La page n'expose plus de picker 7/14/30 jours : on travaille
/// toujours sur 14 nuits glissantes, mais une **timeline visuelle**
/// (`TimelineNuitsVue`) montre lesquelles sont valides et pourquoi les
/// autres sont exclues.
let kFenetreNuits: Int = 14

// MARK: - Modèles de courbe nocturne

/// Un point d'une courbe glycémique nocturne — heure exprimée en
/// **heures depuis 00h** (0.0 → 6.0) pour rester indépendant d'une date
/// calendaire spécifique. Sert à la fois à `Chart` (axe X numérique)
/// et au calcul de la tendance moyenne (interpolation simple par index).
struct PointCourbeNuit: Identifiable, Equatable, Sendable {
    let id = UUID()
    let heure: Double
    let valeur: Double

    static func == (lhs: PointCourbeNuit, rhs: PointCourbeNuit) -> Bool {
        lhs.heure == rhs.heure && lhs.valeur == rhs.valeur
    }
}

/// Catégorisation d'une nuit **valide** pour la répartition.
enum CategorieNuit: Sendable {
    case stable
    case tendanceBasse
    case tendanceHaute
}

/// Une nuit individuelle valide — sa série de points + sa catégorie +
/// ses éventuels points hypos (< 70 mg/dL) à afficher en rouge.
struct CourbeNuit: Identifiable, Sendable {
    let id = UUID()
    let categorie: CategorieNuit
    let points: [PointCourbeNuit]

    /// Points où la valeur passe sous 70 — extraits une seule fois à la
    /// construction pour éviter de re-filtrer à chaque render du chart.
    var pointsHypo: [PointCourbeNuit] {
        points.filter { $0.valeur < 70 }
    }
}

// MARK: - Timeline des nuits

/// Raison textuelle d'exclusion d'une nuit — affichée en popover quand
/// l'utilisateur tape un point gris dans la timeline. Format court qui
/// rentre sur une ligne (`.caption .secondary`).
enum RaisonExclusion: String, Sendable {
    case iobResiduel = "IOB résiduel 1.2u"
    case sportTardif = "Sport à 19h30"
    case repasCopieux = "Repas copieux (85g vs moy. 45g)"
    case cgmIncomplet = "CGM incomplet (62%)"
}

/// État visuel d'une nuit dans la timeline 14 jours.
///
/// L'analyse V1 traite chaque nuit comme un tout — soit on l'inclut
/// (`.valide`), soit on l'exclut (`.exclue` avec raison). Une V2
/// pourrait analyser des **portions** de nuit (par ex. inclure la
/// fenêtre 02h-06h même si une correction a eu lieu à 23h), mais cette
/// granularité ajouterait une couche de logique non-triviale sur le
/// pipeline ML — repoussée volontairement à plus tard.
enum EtatNuit: Sendable, Equatable {
    case valide(categorie: CategorieNuit)
    case exclue(raison: RaisonExclusion)
    case sansDonnees
    case enCours

    static func == (lhs: EtatNuit, rhs: EtatNuit) -> Bool {
        switch (lhs, rhs) {
        case (.valide(let a), .valide(let b)):  return a == b
        case (.exclue(let a), .exclue(let b)):  return a == b
        case (.sansDonnees, .sansDonnees):      return true
        case (.enCours, .enCours):              return true
        default:                                return false
        }
    }

    /// `true` si la nuit a été incluse dans le calcul — pilote la
    /// couleur du point et la ligne verte de connexion.
    var estValide: Bool {
        if case .valide = self { return true }
        return false
    }
}

extension CategorieNuit: Equatable {}

/// Une cellule de la timeline 14 jours.
///
/// Le drapeau `avantChangementDose` permet de griser visuellement les
/// nuits qui précèdent un changement de dose récent : leur glycémie
/// reflète l'ancien réglage et ne devrait pas être moyennée avec les
/// nuits post-changement.
struct NuitTimeline: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let etat: EtatNuit
    let avantChangementDose: Bool
}

// MARK: - Snapshot complet de l'analyse

/// Snapshot prêt-à-afficher pour `DetailAnalyseBasaleVue` — agrège
/// verdict, métriques, courbes et texte LLM pour la fenêtre 14 nuits
/// courante. La forme est volontairement plate : toutes les valeurs
/// sont déjà calculées par le service (pas de logique dans la vue).
struct AnalyseBasaleDetail: Identifiable, Sendable {
    let id = UUID()

    let verdict: VerdictBasale

    // MARK: Contexte « dose »
    let doseActuelle: Double
    /// Date du dernier changement de dose, ou `nil` si aucun changement
    /// récent (> 30 jours). Pilote le libellé contextuel de la carte
    /// verdict (« Depuis le changement de dose ») et le grisage des
    /// colonnes pré-changement dans la timeline.
    let changementDoseRecent: Date?

    // MARK: Métriques agrégées
    let penteMoyenne: Double          // mg/dL/h, signé
    let nuitsAnalysees: Int           // = nuits valides
    let nuitsExclues: Int

    // MARK: Décomposition pour la barre + métriques (sur les valides)
    let nuitsStables: Int
    let nuitsTendanceBasse: Int
    let nuitsTendanceHaute: Int
    let hyposNocturnes: Int
    let resucragesAvecRechute: Int
    let glycemieMoyenneReveil: Int

    // MARK: Courbes pour le chart (uniquement les nuits valides)
    let courbes: [CourbeNuit]
    let tendanceMoyenne: [PointCourbeNuit]

    // MARK: Timeline 14 jours (du plus ancien au plus récent)
    let timeline: [NuitTimeline]

    // MARK: Texte LLM
    let resumeIA: String?
}

// MARK: - Service mock

/// Source unique pour les snapshots mockés de l'analyse basale.
/// Sera remplacé par un vrai service quand la couche ML produira
/// l'analyse — la vue ne dépendra alors que de la forme
/// `AnalyseBasaleDetail`.
enum AnalyseBasaleServiceMock {

    // MARK: - Chargement par verdict

    /// Charge un snapshot pour le verdict demandé. Synchrone et
    /// déterministe — chaque appel avec les mêmes paramètres produit la
    /// même `AnalyseBasaleDetail` (RNG seedé), ce qui stabilise les
    /// previews et les snapshots de test.
    static func charger(verdict: VerdictBasale) -> AnalyseBasaleDetail {
        switch verdict {
        case .adaptee:                return mockAdaptee()
        case .tropHaute:              return mockTropHaute()
        case .tropBasse:              return mockTropBasse()
        case .donneesInsuffisantes:   return mockInsuffisant()
        }
    }

    // MARK: - Variantes par verdict

    /// Verdict « trop haute » sur les 14 dernières nuits — mix réaliste
    /// avec 8 nuits valides, 3 exclues et 3 sans données / en cours.
    static func mockTropHaute() -> AnalyseBasaleDetail {
        construire(
            verdict: .tropHaute,
            seed: 0xBA5_0001,
            penteMoyenne: -2.1,
            // 5 stables + 2 tendances basses (avec 1 hypo) + 1 tendance haute = 8 valides
            stables: 5, basses: 2, hautes: 1,
            // Exclusions : IOB, sport, repas → couvre les 3 raisons hors-CGM
            exclusions: [.iobResiduel, .sportTardif, .repasCopieux],
            sansDonnees: 2,
            hyposNocturnes: 1,
            resucragesAvecRechute: 1,
            glycemieMoyenneReveil: 95,
            doseActuelle: 18,
            changementDoseRecent: nil,
            resumeBuilder: texteIATropHaute
        )
    }

    /// Verdict « adaptée » — quasi toutes les nuits valides sont
    /// stables, pas d'hypo, pente proche de zéro.
    static func mockAdaptee() -> AnalyseBasaleDetail {
        construire(
            verdict: .adaptee,
            seed: 0xBA5_0002,
            penteMoyenne: -0.2,
            stables: 9, basses: 1, hautes: 0,
            exclusions: [.iobResiduel, .repasCopieux],
            sansDonnees: 1,
            hyposNocturnes: 0,
            resucragesAvecRechute: 0,
            glycemieMoyenneReveil: 105,
            doseActuelle: 18,
            changementDoseRecent: nil,
            resumeBuilder: texteIAAdaptee
        )
    }

    /// Verdict « trop basse » — pattern ascendant, glycémie au réveil
    /// au-dessus de la cible, aucune hypo.
    static func mockTropBasse() -> AnalyseBasaleDetail {
        construire(
            verdict: .tropBasse,
            seed: 0xBA5_0003,
            penteMoyenne: 1.8,
            stables: 5, basses: 1, hautes: 3,
            exclusions: [.iobResiduel, .sportTardif, .cgmIncomplet],
            sansDonnees: 1,
            hyposNocturnes: 0,
            resucragesAvecRechute: 0,
            glycemieMoyenneReveil: 165,
            doseActuelle: 18,
            changementDoseRecent: nil,
            resumeBuilder: texteIATropBasse
        )
    }

    /// Verdict « données insuffisantes » — beaucoup d'exclusions, 2-3
    /// nuits valides seulement. Pas de texte LLM (la carte 4 est masquée).
    static func mockInsuffisant() -> AnalyseBasaleDetail {
        construire(
            verdict: .donneesInsuffisantes,
            seed: 0xBA5_0004,
            penteMoyenne: 0,
            stables: 2, basses: 0, hautes: 0,
            exclusions: [.iobResiduel, .sportTardif, .repasCopieux, .cgmIncomplet, .iobResiduel],
            sansDonnees: 6,
            hyposNocturnes: 0,
            resucragesAvecRechute: 0,
            glycemieMoyenneReveil: 110,
            doseActuelle: 18,
            changementDoseRecent: nil,
            resumeBuilder: { _ in nil }
        )
    }

    /// Mock de référence pour les previews — variante de `mockTropHaute`
    /// alignée mot pour mot avec la spec ergonomie (5 stables + 2 basses
    /// dont 1 hypo + 1 haute + 3 exclues + 2 sans CGM + 1 en cours).
    static func mockStandard14j() -> AnalyseBasaleDetail {
        mockTropHaute()
    }

    /// Mock « changement de dose il y a 4 jours » — 3 nuits valides
    /// post-changement, 11 nuits pré-changement grisées dans la timeline.
    /// Le service tronque les courbes / métriques aux nuits
    /// post-changement uniquement, conformément à la pratique clinique
    /// (les données pré-changement reflètent l'ancien réglage).
    static func mockChangementDose() -> AnalyseBasaleDetail {
        let cal = Calendar.current
        let now = Date.now
        let dateChangement = cal.date(byAdding: .day, value: -4, to: now) ?? now

        var rng = SeededRNG(state: 0xBA5_0005 | 1)
        let courbes: [CourbeNuit] = [
            CourbeNuit(categorie: .stable,        points: courbeStable(rng: &rng)),
            CourbeNuit(categorie: .stable,        points: courbeStable(rng: &rng)),
            CourbeNuit(categorie: .tendanceBasse, points: courbeBasse(rng: &rng)),
        ]

        let timeline = construireTimelineChangementDose(
            now: now,
            dateChangement: dateChangement
        )

        return AnalyseBasaleDetail(
            verdict: .tropHaute,
            doseActuelle: 19,
            changementDoseRecent: dateChangement,
            penteMoyenne: -1.4,
            nuitsAnalysees: 3,
            nuitsExclues: 1,
            nuitsStables: 2,
            nuitsTendanceBasse: 1,
            nuitsTendanceHaute: 0,
            hyposNocturnes: 0,
            resucragesAvecRechute: 0,
            glycemieMoyenneReveil: 102,
            courbes: courbes,
            tendanceMoyenne: tendanceMoyenne(courbes),
            timeline: timeline,
            resumeIA: """
            Depuis le changement de dose il y a 4 jours, 3 nuits ont été \
            analysées. Une tendance à la baisse persiste (pente -1.4 mg/dL/h) \
            sans hypo nocturne détectée. La fenêtre reste courte : un verdict \
            plus fiable nécessite au moins 7 nuits post-changement.
            """
        )
    }

    // MARK: - Construction unifiée

    /// Assemble un snapshot à partir des paramètres haut niveau. Centralise
    /// la logique commune (génération de courbes, timeline, total nuits)
    /// pour que chaque variante par verdict n'ait à spécifier que ses
    /// propres chiffres.
    private static func construire(
        verdict: VerdictBasale,
        seed: UInt64,
        penteMoyenne: Double,
        stables: Int, basses: Int, hautes: Int,
        exclusions: [RaisonExclusion],
        sansDonnees: Int,
        hyposNocturnes: Int,
        resucragesAvecRechute: Int,
        glycemieMoyenneReveil: Int,
        doseActuelle: Double,
        changementDoseRecent: Date?,
        resumeBuilder: (Int) -> String?
    ) -> AnalyseBasaleDetail {
        var rng = SeededRNG(state: seed | 1)
        let courbes = genererCourbes(
            rng: &rng,
            stables: stables, basses: basses, hautes: hautes
        )
        let nuitsValides = stables + basses + hautes
        let totalRequis = kFenetreNuits
        // 1 nuit en cours (la nuit courante) + les valides/exclues/sans-données
        let nuitEnCours = 1
        let resteCalc = totalRequis - nuitsValides - exclusions.count - sansDonnees - nuitEnCours
        // Compense automatiquement pour qu'on retombe toujours sur 14 cases.
        let sansDonneesAjustees = max(0, sansDonnees + resteCalc)

        let timeline = construireTimelineStandard(
            stables: stables, basses: basses, hautes: hautes,
            exclusions: exclusions,
            sansDonnees: sansDonneesAjustees
        )

        return AnalyseBasaleDetail(
            verdict: verdict,
            doseActuelle: doseActuelle,
            changementDoseRecent: changementDoseRecent,
            penteMoyenne: penteMoyenne,
            nuitsAnalysees: nuitsValides,
            nuitsExclues: exclusions.count,
            nuitsStables: stables,
            nuitsTendanceBasse: basses,
            nuitsTendanceHaute: hautes,
            hyposNocturnes: hyposNocturnes,
            resucragesAvecRechute: resucragesAvecRechute,
            glycemieMoyenneReveil: glycemieMoyenneReveil,
            courbes: courbes,
            tendanceMoyenne: tendanceMoyenne(courbes),
            timeline: timeline,
            resumeIA: resumeBuilder(nuitsValides)
        )
    }

    // MARK: - Génération des courbes

    private static func genererCourbes(rng: inout SeededRNG, stables: Int, basses: Int, hautes: Int) -> [CourbeNuit] {
        var courbes: [CourbeNuit] = []
        courbes.reserveCapacity(stables + basses + hautes)
        for _ in 0..<stables {
            courbes.append(CourbeNuit(categorie: .stable, points: courbeStable(rng: &rng)))
        }
        for _ in 0..<basses {
            courbes.append(CourbeNuit(categorie: .tendanceBasse, points: courbeBasse(rng: &rng)))
        }
        for _ in 0..<hautes {
            courbes.append(CourbeNuit(categorie: .tendanceHaute, points: courbeHaute(rng: &rng)))
        }
        return courbes
    }

    /// Glycémie stable autour de 90-130 — démarrage aléatoire dans la
    /// cible avec un bruit ±8 mg/dL, sans dérive significative.
    private static func courbeStable(rng: inout SeededRNG) -> [PointCourbeNuit] {
        let base = Double.random(in: 95...125, using: &rng)
        return (0...36).map { i in
            let h = Double(i) / 6.0
            let bruit = Double.random(in: -8...8, using: &rng)
            let derive = sin(Double(i) * 0.35) * 4
            return PointCourbeNuit(heure: h, valeur: base + bruit + derive)
        }
    }

    /// Pattern « basale trop élevée » — démarrage ~120, descente
    /// progressive vers 65-75 sur 6h, avec parfois un point sous 70.
    private static func courbeBasse(rng: inout SeededRNG) -> [PointCourbeNuit] {
        let depart = Double.random(in: 115...130, using: &rng)
        let arrivee = Double.random(in: 62...75, using: &rng)
        return (0...36).map { i in
            let t = Double(i) / 36.0
            let h = Double(i) / 6.0
            let valeur = depart + (arrivee - depart) * t + sin(Double(i) * 0.45) * 5
                + Double.random(in: -3...3, using: &rng)
            return PointCourbeNuit(heure: h, valeur: valeur)
        }
    }

    /// Pattern « basale insuffisante » — démarrage ~100, montée
    /// progressive vers 160-180 sur 6h.
    private static func courbeHaute(rng: inout SeededRNG) -> [PointCourbeNuit] {
        let depart = Double.random(in: 95...110, using: &rng)
        let arrivee = Double.random(in: 160...185, using: &rng)
        return (0...36).map { i in
            let t = Double(i) / 36.0
            let h = Double(i) / 6.0
            let valeur = depart + (arrivee - depart) * t + sin(Double(i) * 0.4) * 6
                + Double.random(in: -3...3, using: &rng)
            return PointCourbeNuit(heure: h, valeur: valeur)
        }
    }

    /// Moyenne point-à-point des courbes — pas d'interpolation
    /// temporelle nécessaire puisque toutes les nuits partagent la même
    /// grille d'index (0...36).
    private static func tendanceMoyenne(_ courbes: [CourbeNuit]) -> [PointCourbeNuit] {
        guard let premier = courbes.first?.points, !premier.isEmpty else { return [] }
        let n = premier.count
        return (0..<n).map { i in
            let valeurs = courbes.map { $0.points[i].valeur }
            let moyenne = valeurs.reduce(0, +) / Double(valeurs.count)
            return PointCourbeNuit(heure: premier[i].heure, valeur: moyenne)
        }
    }

    // MARK: - Construction de la timeline

    /// Construit une timeline 14 jours en mélangeant les états selon
    /// un pattern réaliste (les exclusions ne sont jamais toutes en
    /// début ou fin de fenêtre — elles sont réparties).
    ///
    /// La nuit la plus récente (index 13) est toujours marquée `.enCours`
    /// — c'est la nuit en train de se dérouler, dont les données ne sont
    /// pas encore consolidées.
    private static func construireTimelineStandard(
        stables: Int, basses: Int, hautes: Int,
        exclusions: [RaisonExclusion],
        sansDonnees: Int
    ) -> [NuitTimeline] {
        let cal = Calendar.current
        let now = Date.now

        // Construit la liste des états à placer (hors nuit en cours).
        var etats: [EtatNuit] = []
        etats.append(contentsOf: Array(repeating: EtatNuit.valide(categorie: .stable), count: stables))
        etats.append(contentsOf: Array(repeating: EtatNuit.valide(categorie: .tendanceBasse), count: basses))
        etats.append(contentsOf: Array(repeating: EtatNuit.valide(categorie: .tendanceHaute), count: hautes))
        etats.append(contentsOf: exclusions.map { EtatNuit.exclue(raison: $0) })
        etats.append(contentsOf: Array(repeating: EtatNuit.sansDonnees, count: sansDonnees))

        // Tronque ou complète à 13 (la 14e est la nuit en cours).
        while etats.count > kFenetreNuits - 1 {
            etats.removeLast()
        }
        while etats.count < kFenetreNuits - 1 {
            etats.append(.sansDonnees)
        }

        // Mélange déterministe : on inversise simplement pour avoir une
        // distribution moins « clusterisée » sans dépendre du RNG seedé
        // (qui sert aux courbes). Suffisant pour des mocks lisibles.
        let shuffled = etatsRepartis(etats)

        let cellules: [NuitTimeline] = (0..<(kFenetreNuits - 1)).map { i in
            let date = cal.date(byAdding: .day, value: -(kFenetreNuits - 1 - i), to: now) ?? now
            return NuitTimeline(date: date, etat: shuffled[i], avantChangementDose: false)
        }
        let nuitCourante = NuitTimeline(date: now, etat: .enCours, avantChangementDose: false)
        return cellules + [nuitCourante]
    }

    /// Construit une timeline avec changement de dose il y a 4 jours :
    /// 10 nuits pré-changement (`avantChangementDose = true`, états
    /// variés mais grisés visuellement), 3 nuits valides
    /// post-changement, 1 nuit en cours.
    private static func construireTimelineChangementDose(now: Date, dateChangement: Date) -> [NuitTimeline] {
        let cal = Calendar.current
        // Pré-changement (jour -13 à -4) : mix valide / exclu / sans donnée
        let etatsPreChangement: [EtatNuit] = [
            .valide(categorie: .stable),
            .valide(categorie: .tendanceBasse),
            .exclue(raison: .iobResiduel),
            .valide(categorie: .stable),
            .valide(categorie: .tendanceBasse),
            .sansDonnees,
            .valide(categorie: .tendanceHaute),
            .valide(categorie: .stable),
            .exclue(raison: .sportTardif),
            .valide(categorie: .tendanceBasse),
        ]
        // Post-changement (jour -3 à -1) : 3 nuits valides
        let etatsPostChangement: [EtatNuit] = [
            .valide(categorie: .stable),
            .valide(categorie: .stable),
            .valide(categorie: .tendanceBasse),
        ]

        var cellules: [NuitTimeline] = []
        for (i, etat) in etatsPreChangement.enumerated() {
            let offset = -(kFenetreNuits - 1) + i
            let date = cal.date(byAdding: .day, value: offset, to: now) ?? now
            cellules.append(NuitTimeline(date: date, etat: etat, avantChangementDose: true))
        }
        for (i, etat) in etatsPostChangement.enumerated() {
            let offset = -3 + i
            let date = cal.date(byAdding: .day, value: offset, to: now) ?? now
            cellules.append(NuitTimeline(date: date, etat: etat, avantChangementDose: false))
        }
        // Nuit en cours
        cellules.append(NuitTimeline(date: now, etat: .enCours, avantChangementDose: false))
        return cellules
    }

    /// Répartit les états pour éviter les clusters — un simple
    /// entrelacement par pas de 3 suffit à donner une distribution
    /// visuelle convaincante sans randomisation supplémentaire.
    private static func etatsRepartis(_ etats: [EtatNuit]) -> [EtatNuit] {
        var resultat = Array(repeating: EtatNuit.sansDonnees, count: etats.count)
        var index = 0
        for etat in etats {
            while index < etats.count, !estVide(resultat[index]) {
                index = (index + 1) % etats.count
            }
            resultat[index] = etat
            index = (index + 3) % etats.count
        }
        return resultat
    }

    private static func estVide(_ etat: EtatNuit) -> Bool {
        if case .sansDonnees = etat { return true }
        return false
    }

    // MARK: - Textes LLM mockés

    private static func texteIATropHaute(nuitsValides: Int) -> String? {
        """
        Sur les \(nuitsValides) nuits valides analysées (sur 14 jours), une \
        tendance à la baisse a été observée avec une pente moyenne de \
        -2.1 mg/dL/h. 1 hypo nocturne a été détectée, ayant nécessité plusieurs \
        resucrages. Ce pattern est compatible avec une basale potentiellement \
        trop élevée. La glycémie au réveil reste dans la cible à 95 mg/dL en \
        moyenne.
        """
    }

    private static func texteIATropBasse(nuitsValides: Int) -> String? {
        """
        Sur les \(nuitsValides) nuits valides analysées (sur 14 jours), une \
        tendance à la hausse a été observée avec une pente moyenne de \
        +1.8 mg/dL/h. La glycémie au réveil est en moyenne à 165 mg/dL, \
        au-dessus de la cible. Aucune hypo nocturne détectée. Ce pattern est \
        compatible avec une basale potentiellement insuffisante.
        """
    }

    private static func texteIAAdaptee(nuitsValides: Int) -> String? {
        """
        Sur les \(nuitsValides) nuits valides analysées (sur 14 jours), la \
        glycémie est restée stable avec une pente moyenne proche de zéro. \
        Aucune hypo nocturne détectée. La glycémie au réveil est en cible à \
        105 mg/dL en moyenne. La basale semble bien adaptée.
        """
    }
}

// MARK: - RNG seedé (LCG 64 bits)

/// Linear congruential generator 64-bit — coefficients de Knuth
/// (`MMIX`). Suffisant pour générer des courbes mockées stables ; pas
/// destiné à un usage cryptographique. Permet de garantir que chaque
/// appel à `genererCourbes(seed:)` produit la même sortie.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

// MARK: - Mocks statiques (consommés par les previews)

extension AnalyseBasaleDetail {

    static var mockTropHaute: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockTropHaute()
    }

    static var mockAdaptee: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockAdaptee()
    }

    static var mockTropBasse: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockTropBasse()
    }

    static var mockInsuffisant: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockInsuffisant()
    }

    /// Mock par défaut, aligné mot pour mot sur la spec produit
    /// (5 stables + 2 basses dont 1 hypo + 1 haute + 3 exclues + 2 sans CGM + 1 en cours).
    static var mockStandard14j: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockStandard14j()
    }

    /// Mock « changement de dose il y a 4 jours » — 3 nuits valides
    /// post-changement, le reste grisé dans la timeline.
    static var mockChangementDose: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockChangementDose()
    }
}
