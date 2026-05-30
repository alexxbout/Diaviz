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

// MARK: - Modèles enrichis pour le graphique d'analyse (V2)

/// Un point glycémique daté — sert à la fois aux séries individuelles
/// de `NightChartData.glucoseValues` et à la tendance moyenne calculée
/// par l'extension `Array<NightChartData>.tendanceMoyenne`.
struct GlucosePoint: Identifiable, Sendable, Hashable {
    let id = UUID()
    let time: Date
    let value: Double

    static func == (lhs: GlucosePoint, rhs: GlucosePoint) -> Bool {
        lhs.time == rhs.time && lhs.value == rhs.value
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(time)
        hasher.combine(value)
    }
}

/// Phases d'une nuit utilisées pour le découpage en zones colorées
/// sur la vue « Par nuit » :
///
///   1. `preEndormissement` (avant la lente) — contexte uniquement
///   2. `endormissement` (lente → lente + 2h) — analysée si stable
///   3. `nuitProfonde` (lente + 2h → début dawn) — **cœur du calcul** de pente
///   4. `dawnPhenomenon` (début dawn → réveil) — jamais incluse (hormonal)
///
/// Seules les zones 2 et 3 peuvent contribuer au calcul ; la zone 1
/// reste contextuelle (pré-injection), la zone 4 est exclue par
/// principe (le foie libère du glucose au petit matin, indépendamment
/// de la basale).
enum NightZone: String, CaseIterable, Sendable {
    case preEndormissement
    case endormissement
    case nuitProfonde
    case dawnPhenomenon

    /// Emoji affiché en permanence dans le segment de la barre zones
    /// (visible centré quand le segment est compressé, juxtaposé au
    /// label quand le segment est sélectionné).
    var emoji: String {
        switch self {
        case .preEndormissement:  return "🌙"
        case .endormissement:     return "💉"
        case .nuitProfonde:       return "😴"
        case .dawnPhenomenon:     return "🌅"
        }
    }

    /// Label court affiché à côté de l'emoji quand le segment est actif.
    var label: String {
        switch self {
        case .preEndormissement:  return "Pré-endo."
        case .endormissement:     return "Endormissement"
        case .nuitProfonde:       return "Nuit profonde"
        case .dawnPhenomenon:     return "Dawn"
        }
    }

    /// Teinte de référence — palette pastel-lumineuse alignée sur la
    /// progression naturelle de la nuit (chaud → frais → indigo →
    /// aube). Utilisée par la barre supérieure du chart par-nuit + les
    /// chips de légende.
    var couleur: Color {
        switch self {
        case .preEndormissement:  return Color(red: 230/255, green: 173/255, blue: 187/255) // rose pâle
        case .endormissement:     return Color(red: 170/255, green: 148/255, blue: 215/255) // lavande
        case .nuitProfonde:       return Color(red: 113/255, green: 137/255, blue: 209/255) // indigo doux
        case .dawnPhenomenon:     return Color(red: 245/255, green: 188/255, blue: 130/255) // pêche
        }
    }

    /// Teinte foncée utilisée pour le label du segment actif — choisie
    /// pour passer le contraste AA sur le fond clair du segment.
    var couleurLabelActif: Color {
        switch self {
        case .preEndormissement:  return Color(red:  90/255, green:  88/255, blue:  84/255)
        case .endormissement:     return Color(red:  72/255, green:  63/255, blue: 181/255)
        case .nuitProfonde:       return Color(red:  15/255, green: 110/255, blue:  86/255)
        case .dawnPhenomenon:     return Color(red: 138/255, green:  85/255, blue:  16/255)
        }
    }

    /// Largeur proportionnelle du segment dans la barre quand aucune
    /// zone n'est sélectionnée. La nuit profonde occupe la moitié de la
    /// barre (flex 4 vs 2/2/2) parce qu'elle représente le cœur du
    /// calcul de pente basale.
    var proportionalFlex: CGFloat {
        switch self {
        case .preEndormissement:  return 2
        case .endormissement:     return 2
        case .nuitProfonde:       return 4
        case .dawnPhenomenon:     return 2
        }
    }
}

/// Caractéristique macro d'une portion de courbe glycémique — sert au
/// libellé « Caractéristique » de la grille stats en mode zoom.
enum CurveCharacteristic: String, Sendable {
    case stable        = "Stable"
    case gradualDrop   = "Descente graduelle"
    case steepDrop     = "Descente brutale"
    case gradualRise   = "Montée graduelle"
    case steepRise     = "Montée brutale"
    case chaotic       = "Chaotique"
    case hypoEvent     = "Hypo détectée"
}

/// Définition d'une zone (avec ses bornes temporelles) + caractérisation
/// + événements internes. Les champs `slope`/`characteristic`/`events`
/// sont déjà calculés par le service : la vue se contente d'afficher.
struct ZoneData: Identifiable, Sendable {
    let id = UUID()
    let zone: NightZone
    let timeRange: ClosedRange<Date>
    let slope: Double?
    let characteristic: CurveCharacteristic
    let isAnalyzed: Bool
    let exclusionReason: String?
    let events: [NightEvent]
}

/// Type d'événement ponctuel à annoter sur la courbe.
enum EventType: Sendable {
    case hypo       // < 70 mg/dL — point rouge cerclé blanc
    case rapide     // injection rapide — point bleu cerclé blanc
    case resucrage  // glucides de correction — point vert cerclé blanc
    case repas      // prise de glucides hors correction — point brun cerclé blanc
    case lente      // injection lente — repère vertical violet (rendu via RuleMark, pas via PointMark)
}

/// Un événement ponctuel — affiché sous forme de point (hypo / rapide /
/// resucrage) ou de ligne verticale (lente). `detail` est le texte
/// utilisé dans le tooltip au tap (« 💉 1.5u à 22h45 »).
struct NightEvent: Identifiable, Sendable, Equatable {
    let id = UUID()
    let type: EventType
    let time: Date
    let value: Double
    let detail: String

    static func == (lhs: NightEvent, rhs: NightEvent) -> Bool {
        lhs.id == rhs.id
    }
}

/// Statut global d'une nuit pour la pastille « Statut » de la grille
/// stats sur la vue « Par nuit ».
enum NightStatus: Sendable {
    case valid           // toutes zones analysables OK → vert
    case partiallyValid  // au moins une zone exploitable mais ≥ 1 zone exclue → ambre
    case excluded        // aucune zone exploitable → gris
    case noData          // pas de capteur cette nuit → gris (avec libellé spécifique)
}

/// Snapshot complet d'une nuit prêt à alimenter le graphique d'analyse
/// basale (vues « Toutes » et « Par nuit »). Toutes les valeurs sont
/// pré-calculées par le service — la vue est purement présentationnelle.
struct NightChartData: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let glucoseValues: [GlucosePoint]
    let basaleTime: Date
    let basaleDose: Double
    let startGlucose: Double
    let wakeUpGlucose: Double
    let zones: [ZoneData]
    let events: [NightEvent]
    let overallStatus: NightStatus
    let slopeZone3: Double?
    let motifExclusion: String?
}

extension Array where Element == NightChartData {

    /// Heure moyenne de prise de lente sur l'ensemble — sert à
    /// positionner le repère 💉 sur la vue agrégée « Toutes ».
    /// Renvoie `nil` si l'array est vide.
    var heureLenteMoyenne: Date? {
        guard !isEmpty else { return nil }
        let cal = Calendar.current
        let secondsOfDay: [Int] = self.map { nuit in
            let c = cal.dateComponents([.hour, .minute, .second], from: nuit.basaleTime)
            // Heures du soir (≥ 12h) — on les considère sur le « jour de
            // référence » ; les rares prises après minuit (rarement
            // observées pour la lente) sont ramenées sur le jour suivant.
            let h = c.hour ?? 0
            let s = (h * 3600) + ((c.minute ?? 0) * 60) + (c.second ?? 0)
            return h < 12 ? s + 86_400 : s
        }
        let moyenne = secondsOfDay.reduce(0, +) / secondsOfDay.count
        // Recompose une Date sur la nuit de référence la plus récente.
        let ref = dernierJour
        let total = moyenne % 86_400
        let jourBase = moyenne >= 86_400
            ? (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: ref)) ?? ref)
            : cal.startOfDay(for: ref)
        return jourBase.addingTimeInterval(TimeInterval(total))
    }

    /// Tendance moyenne point-à-point (toutes les nuits partagent la
    /// même grille de samples — voir `AnalyseBasaleServiceMock.genererNuit`).
    /// Le `time` retourné est celui de la première nuit (servira de
    /// référence pour le rendu Chart sur la vue agrégée).
    var tendanceMoyenne: [GlucosePoint] {
        guard let premiere = self.first else { return [] }
        let n = premiere.glucoseValues.count
        guard n > 0 else { return [] }
        return (0..<n).map { i in
            let valeurs = self.map { $0.glucoseValues[i].value }
            let moyenne = valeurs.reduce(0, +) / Double(valeurs.count)
            return GlucosePoint(time: premiere.glucoseValues[i].time, value: moyenne)
        }
    }

    /// Date la plus récente (max sur `.date`) — utilisée comme ancre
    /// pour `heureLenteMoyenne`.
    var dernierJour: Date {
        self.map { $0.date }.max() ?? Date.now
    }
}

// MARK: - Verdict global de l'analyse basale

/// Conclusion synthétique de la sous-analyse basale (B1), telle qu'exposée
/// par la carte sommaire « Analyse du coucher » et utilisée pour router
/// vers le bon snapshot de détail (`charger(verdict:)`).
///
/// Les deux états « hors cible » (`.tropHaute`, `.tropBasse`) partagent
/// volontairement le même libellé « À revoir » côté carte pour ne pas
/// suggérer une direction de correction — l'utilisateur ouvre le détail
/// pour savoir quoi ajuster.
enum VerdictBasale: Sendable, Equatable {

    /// Profil glycémique nocturne stable, basale calibrée.
    case adaptee

    /// Tendance haute sur la fenêtre analysée → ajustement à examiner.
    case tropHaute

    /// Tendance basse sur la fenêtre analysée → ajustement à examiner.
    case tropBasse

    /// Pas assez de nuits exploitables (capteur HS, données récentes).
    case donneesInsuffisantes
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

    // MARK: Données enrichies du graphique d'analyse (V2)
    /// Nuits prêtes à alimenter `GraphiqueAnalyseBasale`. Inclut les
    /// nuits exploitables (valides + partielles) sur la fenêtre 14 jours
    /// — on exclut les nuits sans données CGM puisqu'il n'y a rien à
    /// tracer. Le rendu par tab ("Toutes" / "Par nuit") est piloté
    /// localement par le composant.
    let nightChartData: [NightChartData]

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
            // Mix riche : 3 stables + 2 tendances basses (avec 1 hypo) +
            // 1 tendance haute + 1 outlier haute (hyper marqué) +
            // 1 outlier basse (hypo sévère) = 8 nuits visibles. Les
            // outliers font apparaître des segments rouge/orange clairs
            // sur la vue agrégée.
            stables: 3, basses: 2, hautes: 1,
            exclusions: [.iobResiduel, .sportTardif, .repasCopieux],
            sansDonnees: 2,
            hyposNocturnes: 1,
            resucragesAvecRechute: 1,
            glycemieMoyenneReveil: 95,
            doseActuelle: 18,
            changementDoseRecent: nil,
            resumeBuilder: texteIATropHaute,
            outliersHaute: 1,
            outliersBasse: 1
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

        let nightData = genererNightChartData(
            rngSeed: 0xCD05_DD55,
            stables: 2, basses: 1, hautes: 0,
            hyposATotaliser: 0,
            resucragesATotaliser: 0,
            doseLente: 19
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
            nightChartData: nightData,
            timeline: timeline,
            resumeIA: """
            Depuis le changement de dose il y a 4 jours, 3 nuits ont été \
            analysées. Une tendance à la baisse persiste (pente -1.4 mg/dL/h) \
            sans hypo nocturne détectée. La fenêtre reste courte : un verdict \
            plus fiable nécessite au moins 7 nuits post-changement.
            """
        )
    }

    /// Mock « changement de dose il y a 2 jours, 2 nuits analysées » —
    /// pour la preview du constat en état `.recentChange` (la barre de
    /// progression montre 2/3, encore 1 nuit nécessaire).
    static func mockRecentChange() -> AnalyseBasaleDetail {
        let cal = Calendar.current
        let now = Date.now
        let dateChangement = cal.date(byAdding: .day, value: -2, to: now) ?? now

        var rng = SeededRNG(state: 0xBA5_0006 | 1)
        let courbes: [CourbeNuit] = [
            CourbeNuit(categorie: .stable, points: courbeStable(rng: &rng)),
            CourbeNuit(categorie: .stable, points: courbeStable(rng: &rng)),
        ]
        let timeline = construireTimelineChangementDose(now: now, dateChangement: dateChangement)
        let nightData = genererNightChartData(
            rngSeed: 0xC4A_C0D5,
            stables: 2, basses: 0, hautes: 0,
            hyposATotaliser: 0,
            resucragesATotaliser: 0,
            doseLente: 17
        )

        return AnalyseBasaleDetail(
            verdict: .donneesInsuffisantes,
            doseActuelle: 17,
            changementDoseRecent: dateChangement,
            penteMoyenne: 0,
            nuitsAnalysees: 2,
            nuitsExclues: 0,
            nuitsStables: 2,
            nuitsTendanceBasse: 0,
            nuitsTendanceHaute: 0,
            hyposNocturnes: 0,
            resucragesAvecRechute: 0,
            glycemieMoyenneReveil: 108,
            courbes: courbes,
            tendanceMoyenne: tendanceMoyenne(courbes),
            nightChartData: nightData,
            timeline: timeline,
            resumeIA: nil
        )
    }

    /// Mock contenant des **outliers** marqués — 4 nuits stables + 2
    /// nuits qui partent en vrille (1 hyper sévère qui dépasse 230,
    /// 1 hypo sévère qui plonge sous 60). Sert au preview du chart
    /// « avec valeurs hautes / basses extrêmes ».
    static func mockAvecOutliers() -> AnalyseBasaleDetail {
        // Bypass de `construire` parce que ce dernier passe par
        // `genererCourbes` (legacy `CourbeNuit`) qui ne connaît pas
        // les outliers. On construit l'objet `nightChartData` à la main.
        let nightData = genererNightChartData(
            rngSeed: 0xBA5_0117,
            stables: 4, basses: 0, hautes: 0,
            hyposATotaliser: 0,
            resucragesATotaliser: 0,
            doseLente: 18,
            outliersHaute: 1,
            outliersBasse: 1
        )
        let timeline = construireTimelineStandard(
            stables: 4, basses: 0, hautes: 2,  // outliers comptés comme "haute" pour le timeline
            exclusions: [],
            sansDonnees: 0
        )
        return AnalyseBasaleDetail(
            verdict: .donneesInsuffisantes,
            doseActuelle: 18,
            changementDoseRecent: nil,
            penteMoyenne: 0,
            nuitsAnalysees: 6,
            nuitsExclues: 0,
            nuitsStables: 4,
            nuitsTendanceBasse: 1,
            nuitsTendanceHaute: 1,
            hyposNocturnes: 1,
            resucragesAvecRechute: 0,
            glycemieMoyenneReveil: 135,
            courbes: [],
            tendanceMoyenne: [],
            nightChartData: nightData,
            timeline: timeline,
            resumeIA: nil
        )
    }

    /// Mock dont la tendance moyenne sur la vue agrégée plonge
    /// clairement sous 70 mg/dL — 6 nuits toutes en `basseAvecHypo`,
    /// pas de stables pour diluer l'average. Sert au preview du chart
    /// « tendance qui présente une hypo ».
    static func mockAvecHypoMoyenne() -> AnalyseBasaleDetail {
        construire(
            verdict: .tropHaute,
            seed: 0xBA5_5A11,
            penteMoyenne: -4.8,
            stables: 0, basses: 6, hautes: 0,
            exclusions: [],
            sansDonnees: 0,
            hyposNocturnes: 6,
            resucragesAvecRechute: 3,
            glycemieMoyenneReveil: 75,
            doseActuelle: 18,
            changementDoseRecent: nil,
            resumeBuilder: texteIATropHaute
        )
    }

    /// Mock « aucune nuit analysée » — pour la preview du constat en
    /// état `.noData`. Timeline pleine de « sans données », pas de
    /// `nightChartData`, pas d'historique de dose récent.
    static func mockNoData() -> AnalyseBasaleDetail {
        let cal = Calendar.current
        let now = Date.now
        var timeline: [NuitTimeline] = (0..<(kFenetreNuits - 1)).map { i in
            let date = cal.date(byAdding: .day, value: -(kFenetreNuits - 1 - i), to: now) ?? now
            return NuitTimeline(date: date, etat: .sansDonnees, avantChangementDose: false)
        }
        timeline.append(NuitTimeline(date: now, etat: .enCours, avantChangementDose: false))

        return AnalyseBasaleDetail(
            verdict: .donneesInsuffisantes,
            doseActuelle: 18,
            changementDoseRecent: nil,
            penteMoyenne: 0,
            nuitsAnalysees: 0,
            nuitsExclues: 0,
            nuitsStables: 0,
            nuitsTendanceBasse: 0,
            nuitsTendanceHaute: 0,
            hyposNocturnes: 0,
            resucragesAvecRechute: 0,
            glycemieMoyenneReveil: 0,
            courbes: [],
            tendanceMoyenne: [],
            nightChartData: [],
            timeline: timeline,
            resumeIA: nil
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
        resumeBuilder: (Int) -> String?,
        outliersHaute: Int = 0,
        outliersBasse: Int = 0
    ) -> AnalyseBasaleDetail {
        var rng = SeededRNG(state: seed | 1)
        let courbes = genererCourbes(
            rng: &rng,
            stables: stables, basses: basses, hautes: hautes
        )
        let nuitsValides = stables + basses + hautes + outliersHaute + outliersBasse
        let totalRequis = kFenetreNuits
        // 1 nuit en cours (la nuit courante) + les valides/exclues/sans-données
        let nuitEnCours = 1
        let resteCalc = totalRequis - nuitsValides - exclusions.count - sansDonnees - nuitEnCours
        // Compense automatiquement pour qu'on retombe toujours sur 14 cases.
        let sansDonneesAjustees = max(0, sansDonnees + resteCalc)

        // Timeline : outliers comptés comme « tendance haute/basse » pour
        // ne pas créer de catégorie spéciale dans la timeline (qui
        // n'expose que stable/basse/haute).
        let timeline = construireTimelineStandard(
            stables: stables,
            basses: basses + outliersBasse,
            hautes: hautes + outliersHaute,
            exclusions: exclusions,
            sansDonnees: sansDonneesAjustees
        )

        // Données enrichies du graphique V2 — une `NightChartData` par
        // nuit valide. La répartition `hyposNocturnes` / `resucragesAvecRechute`
        // est répliquée dans les events des nuits concernées pour que la
        // vue « Toutes » montre exactement le bon nombre de points.
        let nightData = genererNightChartData(
            rngSeed: seed ^ 0x4954_4E47,
            stables: stables, basses: basses, hautes: hautes,
            hyposATotaliser: hyposNocturnes,
            resucragesATotaliser: resucragesAvecRechute,
            doseLente: doseActuelle,
            outliersHaute: outliersHaute,
            outliersBasse: outliersBasse
        )

        return AnalyseBasaleDetail(
            verdict: verdict,
            doseActuelle: doseActuelle,
            changementDoseRecent: changementDoseRecent,
            penteMoyenne: penteMoyenne,
            nuitsAnalysees: nuitsValides,
            nuitsExclues: exclusions.count,
            nuitsStables: stables,
            nuitsTendanceBasse: basses + outliersBasse,
            nuitsTendanceHaute: hautes + outliersHaute,
            hyposNocturnes: hyposNocturnes + outliersBasse, // outlier basse = hypo sévère
            resucragesAvecRechute: resucragesAvecRechute,
            glycemieMoyenneReveil: glycemieMoyenneReveil,
            courbes: courbes,
            tendanceMoyenne: tendanceMoyenne(courbes),
            nightChartData: nightData,
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

    // MARK: - Génération `NightChartData` (V2)

    /// Pattern glycémique pour une nuit du chart V2 — décide la forme
    /// macro de la courbe (descente, montée, oscillation zone 2, etc.).
    enum NightPattern {
        case stable
        case basseLente        // basale trop élevée → descente lente
        case basseAvecHypo     // descente + dip < 70 quelque part en zone 3
        case haute             // basale insuffisante → montée
        case chaotiqueZone2    // zone 2 oscille (correction tardive ou rebond)
        case outlierHaute      // hyper marquée — dépasse 230 (stress, repas tardif riche…)
        case outlierBasse      // hypo sévère — plonge < 55 (alcool, sport non comptabilisé…)
    }

    /// Construit `count` nuits où `count = stables + basses + hautes
    /// + outliersHaute + outliersBasse`.
    /// Insère ensuite jusqu'à `hyposATotaliser` dips < 70 sur les nuits
    /// `.basseLente` (transformées en `.basseAvecHypo`) et
    /// `resucragesATotaliser` events resucrage sur les nuits où une
    /// hypo a été placée.
    static func genererNightChartData(
        rngSeed: UInt64,
        stables: Int, basses: Int, hautes: Int,
        hyposATotaliser: Int,
        resucragesATotaliser: Int,
        doseLente: Double,
        outliersHaute: Int = 0,
        outliersBasse: Int = 0
    ) -> [NightChartData] {
        var rng = SeededRNG(state: rngSeed | 1)
        var patterns: [NightPattern] = []
        // On promeut `hyposATotaliser` nuits `.basseLente` en `.basseAvecHypo`.
        let bassesAvecHypo = min(hyposATotaliser, basses)
        let bassesSansHypo = basses - bassesAvecHypo
        patterns.append(contentsOf: Array(repeating: .stable, count: stables))
        patterns.append(contentsOf: Array(repeating: .basseLente, count: bassesSansHypo))
        patterns.append(contentsOf: Array(repeating: .basseAvecHypo, count: bassesAvecHypo))
        patterns.append(contentsOf: Array(repeating: .haute, count: hautes))
        patterns.append(contentsOf: Array(repeating: .outlierHaute, count: outliersHaute))
        patterns.append(contentsOf: Array(repeating: .outlierBasse, count: outliersBasse))

        // Resucrage placé seulement sur les nuits avec hypo (un rebond
        // jaune-puis-vert visuellement parlant).
        var resucragesRestants = min(resucragesATotaliser, bassesAvecHypo)

        let cal = Calendar.current
        let now = Date.now
        var nuits: [NightChartData] = []
        for (idx, pattern) in patterns.enumerated() {
            let dateNuit = cal.date(byAdding: .day, value: -(idx + 1), to: now) ?? now
            let avecResucrage = (pattern == .basseAvecHypo) && (resucragesRestants > 0)
            if avecResucrage { resucragesRestants -= 1 }
            nuits.append(genererNuit(
                date: dateNuit,
                pattern: pattern,
                doseLente: doseLente,
                avecResucrage: avecResucrage,
                rng: &rng
            ))
        }
        return nuits
    }

    /// Construit une `NightChartData` complète pour une nuit unique.
    /// La grille temporelle est fixée : 121 samples à pas constant de
    /// 5 min entre 21h00 et 7h00 — ce qui permet une moyenne point-à-
    /// point triviale sur la vue agrégée.
    private static func genererNuit(
        date: Date,
        pattern: NightPattern,
        doseLente: Double,
        avecResucrage: Bool,
        rng: inout SeededRNG
    ) -> NightChartData {
        let cal = Calendar.current
        let veille = cal.startOfDay(for: date)
        let lendemain = cal.date(byAdding: .day, value: 1, to: veille) ?? veille

        // Bornes du graphique : 21h00 (veille) → 7h00 (lendemain).
        let debut = cal.date(bySettingHour: 21, minute: 0, second: 0, of: veille) ?? veille
        // Prise de lente vers 22h30 ± 15min.
        let basaleMinute = 30 + Int.random(in: -15...15, using: &rng)
        let basaleHeure = basaleMinute < 0 ? 21 : 22
        let basaleMin = (basaleMinute + 60) % 60
        let basaleTime = cal.date(bySettingHour: basaleHeure, minute: basaleMin, second: 0, of: veille) ?? debut

        // Glycémies — 121 samples à pas 5 min.
        let nbSamples = 121
        var points: [GlucosePoint] = []
        points.reserveCapacity(nbSamples)
        let depart = Double.random(in: 105...130, using: &rng)
        for i in 0..<nbSamples {
            let temps = debut.addingTimeInterval(TimeInterval(i * 300))
            let t = Double(i) / Double(nbSamples - 1) // 0...1
            let valeur = glycemiePour(
                pattern: pattern,
                t: t,
                depart: depart,
                temps: temps,
                lente: basaleTime,
                cal: cal,
                rng: &rng
            )
            points.append(GlucosePoint(time: temps, value: valeur))
        }

        // Zones — calées sur la lente, avec un dawn fixé à 5h00.
        let dawnDebut = cal.date(bySettingHour: 5, minute: 0, second: 0, of: lendemain) ?? lendemain
        let fin = cal.date(bySettingHour: 7, minute: 0, second: 0, of: lendemain) ?? lendemain
        let endormissementFin = basaleTime.addingTimeInterval(2 * 3600)

        // Construction asynchrone : on a besoin des events pour les
        // découper par zone — donc on génère d'abord les events, puis
        // les zones (qui réutilisent ces events filtrés).
        let eventsAvantZones = construireEventsPour(
            pattern: pattern,
            points: points,
            basaleTime: basaleTime,
            doseLente: doseLente,
            avecResucrage: avecResucrage,
            endormissementFin: endormissementFin,
            dawnDebut: dawnDebut,
            cal: cal,
            veille: veille
        )

        let zones = construireZones(
            pattern: pattern,
            points: points,
            events: eventsAvantZones,
            debut: debut,
            basaleTime: basaleTime,
            endormissementFin: endormissementFin,
            dawnDebut: dawnDebut,
            fin: fin
        )

        // Pente zone 3 — lue directement depuis la zone construite plus haut.
        let slope = zones.first(where: { $0.zone == .nuitProfonde })?.slope

        // Statut global.
        let status: NightStatus
        switch pattern {
        case .chaotiqueZone2:  status = .partiallyValid
        default:               status = .valid
        }

        let motif: String? = (pattern == .chaotiqueZone2)
            ? zones.first(where: { $0.zone == .endormissement })?.exclusionReason
            : nil

        // Glycémie de départ (au moment de la lente) et au réveil.
        let startGluc = points.first(where: { abs($0.time.timeIntervalSince(basaleTime)) < 300 })?.value ?? depart
        let wakeGluc = points.last?.value ?? depart

        return NightChartData(
            date: date,
            glucoseValues: points,
            basaleTime: basaleTime,
            basaleDose: doseLente,
            startGlucose: startGluc,
            wakeUpGlucose: wakeGluc,
            zones: zones,
            events: eventsAvantZones,
            overallStatus: status,
            slopeZone3: slope,
            motifExclusion: motif
        )
    }

    // MARK: Sous-helpers de `genererNuit`

    /// Construit la liste plate des events de la nuit (lente + rapide +
    /// éventuels hypos + éventuels resucrages). Ordre temporel non
    /// garanti — le consommateur trie si besoin.
    private static func construireEventsPour(
        pattern: NightPattern,
        points: [GlucosePoint],
        basaleTime: Date,
        doseLente: Double,
        avecResucrage: Bool,
        endormissementFin: Date,
        dawnDebut: Date,
        cal: Calendar,
        veille: Date
    ) -> [NightEvent] {
        var events: [NightEvent] = []
        // Lente — repère vertical (le rendu de la « ligne » se fait via
        // RuleMark dans la vue, pas via PointMark).
        events.append(NightEvent(
            type: .lente,
            time: basaleTime,
            value: 0,
            detail: "💉 \(formate(doseLente))u à \(heureCourte(basaleTime))"
        ))
        // Encas tardif ~21h30 (pré-endormissement) — sert à donner du
        // contexte sur la zone 1 et à montrer les points repas sur le
        // graphique de cette zone.
        let repasTime = cal.date(bySettingHour: 21, minute: 30, second: 0, of: veille) ?? basaleTime
        if let repasValeur = pointProche(repasTime, dans: points) {
            events.append(NightEvent(
                type: .repas,
                time: repasTime,
                value: repasValeur,
                detail: "🍽️ 20g à \(heureCourte(repasTime))"
            ))
        }
        // Rapide post-dîner ~22h45.
        let rapideTime = cal.date(bySettingHour: 22, minute: 45, second: 0, of: veille) ?? basaleTime
        if let rapideValeur = pointProche(rapideTime, dans: points) {
            events.append(NightEvent(
                type: .rapide,
                time: rapideTime,
                value: rapideValeur,
                detail: "💉 1.5u à \(heureCourte(rapideTime))"
            ))
        }
        // Hypo — point le plus bas en zone 3 si pattern .basseAvecHypo.
        if pattern == .basseAvecHypo {
            let z3 = points.filter { endormissementFin...dawnDebut ~= $0.time }
            if let pire = z3.min(by: { $0.value < $1.value }) {
                events.append(NightEvent(
                    type: .hypo,
                    time: pire.time,
                    value: pire.value,
                    detail: "⚠️ \(Int(pire.value)) mg/dL à \(heureCourte(pire.time))"
                ))
            }
        }
        // Resucrage ~20 min après l'hypo.
        if avecResucrage, let hypo = events.first(where: { $0.type == .hypo }) {
            let tempsResucrage = hypo.time.addingTimeInterval(20 * 60)
            if let valeur = pointProche(tempsResucrage, dans: points) {
                events.append(NightEvent(
                    type: .resucrage,
                    time: tempsResucrage,
                    value: valeur,
                    detail: "🍬 15g à \(heureCourte(tempsResucrage))"
                ))
            }
        }
        return events
    }

    /// Construit les 4 zones avec leurs métadonnées calculées :
    /// pente locale, caractéristique macro, événements internes,
    /// raison d'exclusion si applicable.
    private static func construireZones(
        pattern: NightPattern,
        points: [GlucosePoint],
        events: [NightEvent],
        debut: Date,
        basaleTime: Date,
        endormissementFin: Date,
        dawnDebut: Date,
        fin: Date
    ) -> [ZoneData] {
        let z1Range = debut...basaleTime
        let z2Range = basaleTime...endormissementFin
        let z3Range = endormissementFin...dawnDebut
        let z4Range = dawnDebut...fin

        func eventsDans(_ range: ClosedRange<Date>) -> [NightEvent] {
            // Exclut la lente — elle est rendue à part en tant que repère.
            events.filter { $0.type != .lente && range.contains($0.time) }
        }

        func ptsDans(_ range: ClosedRange<Date>) -> [GlucosePoint] {
            points.filter { range.contains($0.time) }
        }

        let z1Events = eventsDans(z1Range)
        let z2Events = eventsDans(z2Range)
        let z3Events = eventsDans(z3Range)
        let z4Events = eventsDans(z4Range)

        let (z1Char, z1Slope) = caracteriserZone(points: ptsDans(z1Range),
                                                 hasHypo: z1Events.contains { $0.type == .hypo })
        let (z2CharBrut, z2Slope) = caracteriserZone(points: ptsDans(z2Range),
                                                    hasHypo: z2Events.contains { $0.type == .hypo })
        let (z3Char, z3Slope) = caracteriserZone(points: ptsDans(z3Range),
                                                 hasHypo: z3Events.contains { $0.type == .hypo })
        let (z4Char, z4Slope) = caracteriserZone(points: ptsDans(z4Range),
                                                 hasHypo: false)

        // Pour le pattern chaotiqueZone2, on force la caractéristique
        // et on rajoute le motif d'exclusion.
        let z2Char: CurveCharacteristic = (pattern == .chaotiqueZone2) ? .chaotic : z2CharBrut
        let z2Analyzed = (pattern != .chaotiqueZone2)
        let z2Exclusion = z2Analyzed ? nil : "Oscillations marquées — correction tardive suspectée"

        return [
            ZoneData(
                zone: .preEndormissement,
                timeRange: z1Range,
                slope: z1Slope,
                characteristic: z1Char,
                isAnalyzed: false,
                exclusionReason: nil,
                events: z1Events
            ),
            ZoneData(
                zone: .endormissement,
                timeRange: z2Range,
                slope: z2Slope,
                characteristic: z2Char,
                isAnalyzed: z2Analyzed,
                exclusionReason: z2Exclusion,
                events: z2Events
            ),
            ZoneData(
                zone: .nuitProfonde,
                timeRange: z3Range,
                slope: z3Slope,
                characteristic: z3Char,
                isAnalyzed: true,
                exclusionReason: nil,
                events: z3Events
            ),
            ZoneData(
                zone: .dawnPhenomenon,
                timeRange: z4Range,
                slope: z4Slope,
                characteristic: z4Char,
                isAnalyzed: false,
                exclusionReason: nil,
                events: z4Events
            ),
        ]
    }

    /// Caractérise une portion de courbe : calcule la pente (premier vs
    /// dernier point, mg/dL/h) et le « régime » macro (stable, descente
    /// graduelle, chaotique, …) via le coefficient de variation.
    static func caracteriserZone(points: [GlucosePoint], hasHypo: Bool) -> (CurveCharacteristic, Double?) {
        guard let premier = points.first, let dernier = points.last,
              points.count >= 2,
              dernier.time > premier.time
        else { return (.stable, nil) }
        let dh = dernier.time.timeIntervalSince(premier.time) / 3600
        let pente = (dernier.value - premier.value) / dh
        // CV (écart-type / moyenne) — au-delà de 0.18 on parle de
        // chaotique (oscillations marquées dépassant ~25 mg/dL autour
        // d'une moyenne ~140).
        let moyenne = points.map(\.value).reduce(0, +) / Double(points.count)
        let variance = points.map { pow($0.value - moyenne, 2) }.reduce(0, +) / Double(points.count)
        let cv = sqrt(variance) / max(moyenne, 1)

        if cv > 0.18 {
            return (.chaotic, pente)
        }
        if hasHypo {
            return (.hypoEvent, pente)
        }
        switch pente {
        case ..<(-1.5):       return (.steepDrop, pente)
        case -1.5..<(-0.3):   return (.gradualDrop, pente)
        case 0.3..<1.5:       return (.gradualRise, pente)
        case 1.5...:          return (.steepRise, pente)
        default:              return (.stable, pente)
        }
    }

    /// Renvoie la glycémie du point le plus proche d'un instant donné,
    /// dans une fenêtre de tolérance de ±2.5 min.
    private static func pointProche(_ instant: Date, dans points: [GlucosePoint]) -> Double? {
        points.first(where: { abs($0.time.timeIntervalSince(instant)) < 150 })?.value
    }

    /// Formule la valeur glycémique à l'instant `t` (0...1) selon le
    /// pattern macro. Pas physiologique — vise une courbe **lisible**
    /// pour la démo.
    private static func glycemiePour(
        pattern: NightPattern,
        t: Double,
        depart: Double,
        temps: Date,
        lente: Date,
        cal: Calendar,
        rng: inout SeededRNG
    ) -> Double {
        let bruit = Double.random(in: -4...4, using: &rng)
        switch pattern {
        case .stable:
            // Variations douces autour de la cible.
            return depart + sin(t * .pi * 2) * 8 + bruit

        case .basseLente:
            // Descente progressive depuis 22h30 (post-pic dîner) jusqu'à
            // 5h00 — environ 25 mg/dL d'écart total.
            let descente = -25 * smoothstep(0.2, 0.9, t)
            return depart + descente + sin(t * .pi * 1.5) * 4 + bruit

        case .basseAvecHypo:
            // Même profil que `.basseLente` mais avec creux marqué vers
            // 4h-5h (t ≈ 0.7). Amplitude -22 mg/dL pour qu'une moyenne
            // sur plusieurs nuits hypo plonge bien sous 70.
            let descente = -35 * smoothstep(0.2, 0.75, t)
            let creux = -22 * bell(center: 0.72, width: 0.08, t: t)
            return depart + descente + creux + bruit

        case .haute:
            // Montée progressive 100 → 175.
            let montee = 60 * smoothstep(0.3, 1.0, t)
            return depart + montee + sin(t * .pi * 1.2) * 4 + bruit

        case .chaotiqueZone2:
            // Oscillations marquées dans la zone 2 (22h30 → 0h30).
            let dansZ2 = temps >= lente && temps < lente.addingTimeInterval(2 * 3600)
            if dansZ2 {
                return depart + sin(t * 60) * 35 + bruit * 2
            }
            // Reste du temps : profil stable.
            return depart + sin(t * .pi * 2) * 8 + bruit

        case .outlierHaute:
            // Montée brutale jusqu'à ~230-250, plateau en deuxième moitié.
            // Sert au preview « valeurs hautes » pour montrer le segment
            // de courbe coloré au-dessus de 180.
            let depart2 = max(depart, 130)
            let montee = 105 * smoothstep(0.15, 0.65, t)
            return depart2 + montee + sin(t * .pi * 2) * 6 + bruit

        case .outlierBasse:
            // Plongeon brutal jusqu'à ~50, remontée éventuelle. Sert au
            // preview « hypo sévère » pour montrer le segment de courbe
            // coloré sous 70.
            let chute = -75 * smoothstep(0.2, 0.6, t)
            let remontee = 25 * smoothstep(0.7, 0.95, t)
            return depart + chute + remontee + bruit
        }
    }

    /// Sigmoïde lisse `smoothstep` (Hermite cubic) : 0 → 1 entre
    /// `edge0` et `edge1`.
    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Gaussienne normalisée 0...1 (cloche d'amplitude 1, centrée sur
    /// `center`, largeur ~`width`). Sert au creux des hypos.
    private static func bell(center: Double, width: Double, t: Double) -> Double {
        let z = (t - center) / width
        return exp(-z * z)
    }

    /// « 22h45 » — format heure courte « francais », séparateur « h »
    /// plutôt que « : » pour rester aligné sur l'usage hospitalier
    /// français (et matcher le wording de la spec produit).
    static func heureCourte(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%dh%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// « 1.5 » / « 1 » selon que la dose est entière ou non.
    private static func formate(_ d: Double) -> String {
        d == floor(d) ? String(format: "%.0f", d) : String(format: "%.1f", d)
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

// MARK: - Modèles dérivés V3 (constat, distribution, historique de dose)

/// Tendance dégagée par l'analyse de la pente moyenne zone 3 — pilote
/// l'icône et la couleur du constat dans `CarteVerdictBasale`.
enum BasalTrend: Sendable {
    case descending
    case ascending
    case stable
}

/// État global du constat — permet à la carte de basculer entre 3
/// rendus visuels distincts (verdict / nouvelle dose en observation /
/// en attente de données).
enum BasalVerdictState: Sendable {
    case sufficient
    case recentChange
    case noData
}

/// Snapshot du constat affiché par `CarteVerdictBasale`. Pré-calculé
/// par `AnalyseBasaleDetail.basalVerdict` — la vue est purement
/// présentationnelle.
struct BasalVerdict: Sendable {
    let state: BasalVerdictState
    let slope: Double?           // pente moyenne zone 3, nil hors `.sufficient`
    let trend: BasalTrend?
    let validNights: Int
    let excludedNights: Int
    let totalNights: Int
    let currentDose: Double
    let doseChangedDate: Date?
    let nightsNeeded: Int        // = max(0, 3 - validNights)
}

/// Répartition de la qualité des zones analysées (zones 2 + 3 — seules
/// concernées par le calcul de pente basale). Alimente `RepartitionNuitsVue`.
struct BasalDistribution: Sendable {
    let stableZones: Int
    let descendingZones: Int
    let ascendingZones: Int
    let excludedZones: Int
    let hypoCount: Int
    let resucrageCount: Int
    let avgWakeUpGlucose: Double
}

/// Une entrée de l'historique de dose. `endDate == nil` ⇔ dose
/// courante.
struct DoseChange: Identifiable, Sendable {
    let id = UUID()
    let dose: Double
    let startDate: Date
    let endDate: Date?
    var isCurrent: Bool { endDate == nil }
}

// MARK: - Helpers dérivés (sur AnalyseBasaleDetail)

extension AnalyseBasaleDetail {

    /// Construit le constat à partir des métriques agrégées :
    ///   - 0 nuit valide → `.noData`
    ///   - 1-2 nuits valides → `.recentChange` (généralement après un
    ///     reset de dose ; on affiche la progression vers les 3 nuits
    ///     minimum)
    ///   - ≥ 3 nuits valides → `.sufficient`, verdict possible.
    var basalVerdict: BasalVerdict {
        let valides = nuitsAnalysees
        let nightsNeeded = max(0, 3 - valides)
        let state: BasalVerdictState = {
            if valides == 0 { return .noData }
            if valides < 3 { return .recentChange }
            return .sufficient
        }()

        let trend: BasalTrend? = {
            guard state == .sufficient else { return nil }
            switch penteMoyenne {
            case ..<(-0.3):  return .descending
            case 0.3...:     return .ascending
            default:         return .stable
            }
        }()

        return BasalVerdict(
            state: state,
            slope: state == .sufficient ? penteMoyenne : nil,
            trend: trend,
            validNights: valides,
            excludedNights: nuitsExclues,
            totalNights: kFenetreNuits,
            currentDose: doseActuelle,
            doseChangedDate: changementDoseRecent,
            nightsNeeded: nightsNeeded
        )
    }

    /// Catégorise les zones 2/3 de toutes les nuits du dataset selon
    /// leur pente et leur statut « analysée ». Les zones 1 (pré-endo)
    /// et 4 (dawn) sont exclues — elles ne participent jamais au
    /// calcul de pente basale.
    ///
    /// Variante non-filtrée : utilise toutes les nuits du dataset
    /// (équivaut à `basalDistribution(daysBack: kFenetreNuits)` pour
    /// le dataset standard).
    var basalDistribution: BasalDistribution {
        basalDistribution(daysBack: kFenetreNuits)
    }

    /// Variante filtrée par fenêtre temporelle — utilisée par le
    /// picker 7j / 14j / 30j de `RepartitionNuitsVue`. Les `hypoCount`,
    /// `resucrageCount` et `avgWakeUpGlucose` sont aussi recalculés
    /// **sur la fenêtre filtrée** (à partir des events de chaque nuit),
    /// pour rester cohérents avec la barre.
    func basalDistribution(daysBack: Int) -> BasalDistribution {
        let cal = Calendar.current
        let cutoffJour = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysBack, to: Date.now) ?? Date.now)
        let nuitsFiltrees = nightChartData.filter { cal.startOfDay(for: $0.date) >= cutoffJour }

        var stable = 0
        var descending = 0
        var ascending = 0
        var excluded = 0
        var hypos = 0
        var resucrages = 0
        var sommeReveil = 0.0
        for night in nuitsFiltrees {
            for zd in night.zones where zd.zone == .endormissement || zd.zone == .nuitProfonde {
                if !zd.isAnalyzed {
                    excluded += 1
                } else if let s = zd.slope {
                    if s < -1 { descending += 1 }
                    else if s > 1 { ascending += 1 }
                    else { stable += 1 }
                } else {
                    stable += 1
                }
            }
            for ev in night.events {
                switch ev.type {
                case .hypo:       hypos += 1
                case .resucrage:  resucrages += 1
                default:          break
                }
            }
            sommeReveil += night.wakeUpGlucose
        }
        let moyReveil = nuitsFiltrees.isEmpty ? 0 : sommeReveil / Double(nuitsFiltrees.count)
        return BasalDistribution(
            stableZones: stable,
            descendingZones: descending,
            ascendingZones: ascending,
            excludedZones: excluded,
            hypoCount: hypos,
            resucrageCount: resucrages,
            avgWakeUpGlucose: moyReveil
        )
    }

    /// Historique de dose mocké — 4 changements sur ~75 jours, dose
    /// courante en haut. Sera remplacé par la couche médication quand
    /// elle sera branchée.
    ///
    /// Si l'analyse est en état `.noData`, on renvoie une seule
    /// entrée (la dose courante posée il y a longtemps) — c'est ce qui
    /// pilote le récap « Aucun changement depuis X jours » de
    /// `DoseHistoryCard`.
    var doseHistory: [DoseChange] {
        let cal = Calendar.current
        let now = Date.now
        func date(_ daysAgo: Int) -> Date {
            cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }
        let courant = changementDoseRecent ?? date(45)
        let entryCourante = DoseChange(dose: doseActuelle, startDate: courant, endDate: nil)

        if nuitsAnalysees == 0 {
            return [entryCourante]
        }

        return [
            entryCourante,
            DoseChange(dose: doseActuelle - 1, startDate: date(75),  endDate: courant),
            DoseChange(dose: doseActuelle - 2, startDate: date(110), endDate: date(75)),
            DoseChange(dose: doseActuelle - 1, startDate: date(140), endDate: date(110)),
        ]
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

    /// Mock « changement de dose il y a 2 jours, encore 1 nuit
    /// nécessaire » — pour la preview du constat en état
    /// `.recentChange`.
    static var mockRecentChange: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockRecentChange()
    }

    /// Mock « aucune nuit analysée » — pour la preview du constat en
    /// état `.noData`.
    static var mockNoData: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockNoData()
    }

    /// Mock dont la tendance moyenne plonge sous 70 mg/dL — pour la
    /// preview du chart « Toutes » avec hypo sur la moyenne.
    static var mockAvecHypoMoyenne: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockAvecHypoMoyenne()
    }

    /// Mock avec 2 nuits outliers (1 hyper sévère, 1 hypo sévère) +
    /// 4 stables — pour la preview du chart « valeurs extrêmes ».
    static var mockAvecOutliers: AnalyseBasaleDetail {
        AnalyseBasaleServiceMock.mockAvecOutliers()
    }
}

// MARK: - Mocks `NightChartData` standalone (consommés par les previews
// du composant graphique)

extension NightChartData {

    /// Nuit valide « manuel » avec pente zone 3 ≈ -1.8 mg/dL/h, sans
    /// hypo ni resucrage. Sert au preview « Par nuit — valide ».
    static var mockNuitValide: NightChartData {
        var rng = SeededRNG(state: 0xCAFE_C0DE)
        let n = AnalyseBasaleServiceMock.genererNightChartData(
            rngSeed: 0xCAFE_C0DE,
            stables: 0, basses: 1, hautes: 0,
            hyposATotaliser: 0,
            resucragesATotaliser: 0,
            doseLente: 18
        ).first!
        _ = rng.next() // garde la même seed pour reproductibilité
        return n
    }

    /// Nuit partiellement valide : zone 2 chaotique (oscillations),
    /// zone 3 toujours analysable. Sert au preview « Par nuit —
    /// partielle ».
    static var mockNuitPartielle: NightChartData {
        AnalyseBasaleServiceMock.genererNightChartData(
            rngSeed: 0xFEED_FACE,
            stables: 0, basses: 0, hautes: 0,
            hyposATotaliser: 0,
            resucragesATotaliser: 0,
            doseLente: 18
        ).first ?? AnalyseBasaleServiceMock.nuitMockParDefaut(chaotique: true)
    }
}

extension AnalyseBasaleServiceMock {

    /// Génère **une seule** nuit par appel direct du helper —
    /// nécessaire pour le mock partiel parce que `genererNightChartData`
    /// avec 0 nuits valides renvoie un tableau vide. Centralise le
    /// pattern « single-night mock » pour ne pas dupliquer le branchement
    /// `cal.date(bySettingHour:)`.
    static func nuitMockParDefaut(chaotique: Bool) -> NightChartData {
        var rng = SeededRNG(state: 0xFEED_FACE)
        return genererNuitDemo(pattern: chaotique ? .chaotiqueZone2 : .stable, rng: &rng)
    }

    /// Wrapper public-au-module sur `genererNuit` pour les besoins du
    /// mock partiel — résout l'accès privé sans exposer toute la
    /// machinerie de génération.
    private static func genererNuitDemo(pattern: NightPattern, rng: inout SeededRNG) -> NightChartData {
        // Stub : on délègue au helper privé en construisant la même
        // shape qu'une nuit standard.
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -1, to: Date.now) ?? Date.now
        return genererNuit(
            date: date,
            pattern: pattern,
            doseLente: 18,
            avecResucrage: false,
            rng: &rng
        )
    }
}
