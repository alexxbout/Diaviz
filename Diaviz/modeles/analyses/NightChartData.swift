//
//  NightChartData.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Modèles enrichis pour le graphique d'analyse (V2)

/// Un point glycémique daté — sert à la fois aux séries individuelles
/// de `NightChartData.glucoseValues` et à la tendance moyenne calculée
/// par l'extension `Array<NightChartData>.tendanceMoyenne`.
nonisolated struct GlucosePoint: Identifiable, Sendable, Hashable {
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
nonisolated enum NightZone: String, CaseIterable, Sendable {
    case preEndormissement
    case endormissement
    case nuitProfonde
    case dawnPhenomenon

    /// SF Symbol affiché en permanence dans le segment de la barre zones
    /// (visible centré quand le segment est compressé, juxtaposé au
    /// label quand le segment est sélectionné).
    var icone: String {
        switch self {
        case .preEndormissement:  return "moon.fill"
        case .endormissement:     return "syringe.fill"
        case .nuitProfonde:       return "bed.double.fill"
        case .dawnPhenomenon:     return "sunrise.fill"
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
nonisolated enum CurveCharacteristic: String, Sendable {
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
nonisolated struct ZoneData: Identifiable, Sendable {
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
nonisolated enum EventType: Sendable {
    case hypo       // < 70 mg/dL — point rouge cerclé blanc
    case rapide     // injection rapide — point bleu cerclé blanc
    case resucrage  // glucides de correction — point vert cerclé blanc
    case repas      // prise de glucides hors correction — point brun cerclé blanc
    case lente      // injection lente — repère vertical violet (rendu via RuleMark, pas via PointMark)
}

/// Un événement ponctuel — affiché sous forme de point (hypo / rapide /
/// resucrage) ou de ligne verticale (lente). `detail` est le texte
/// utilisé dans le tooltip au tap (« 💉 1.5u à 22h45 »).
nonisolated struct NightEvent: Identifiable, Sendable, Equatable {
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
nonisolated enum NightStatus: Sendable {
    case valid           // toutes zones analysables OK → vert
    case partiallyValid  // au moins une zone exploitable mais ≥ 1 zone exclue → ambre
    case excluded        // aucune zone exploitable → gris
    case noData          // pas de capteur cette nuit → gris (avec libellé spécifique)
}

/// Taxonomie des épisodes hypo d'une nuit — calculée sur la **fenêtre de
/// sommeil complète** (endormissement → fin de nuit, zone 4 incluse : une
/// hypo à 4h45 reste une hypo, même si la zone dawn est exclue de la dérive).
///
/// Quatre patterns distincts, quatre signaux :
///   - **prolongée** : un épisode continu sous le seuil ≥ 30 min (ne remonte pas)
///   - **en série** : épisodes rapprochés **sans repas entre eux** — la glycémie
///     rase le seuil (remonte à peine puis retombe)
///   - **rechute** : resucrage loggé → remontée → nouvelle hypo < 60 min
///     (sous-correction ; n'existe que si un repas est loggé)
///   - **spontanée / resucrée** : l'épisode est-il remonté seul (aucun repas
///     loggé → contre-régulation, fin d'action ou compression capteur) ou
///     après resucrage ?
nonisolated struct BilanHyposNuit: Sendable, Equatable {
    /// Total d'épisodes hypo (points contigus < 70) sur la fenêtre de sommeil.
    var episodes: Int = 0
    /// Épisodes dont le point bas tombe après l'endormissement (zones 3+4) —
    /// seuls déclencheurs du verdict basale (zone 2 = plutôt dîner/bolus).
    var episodesProfonds: Int = 0
    /// Épisodes restés sous le seuil en continu ≥ `dureeProlongeeMin`.
    var prolongees: Int = 0
    /// Épisodes appartenant à un cluster (< 60 min d'écart, sans repas entre).
    var enSerie: Int = 0
    /// Resucrages loggés suivis d'une nouvelle hypo < 60 min.
    var rechutes: Int = 0
    /// Épisodes avec repas loggé pendant l'hypo (resucrage).
    var resucrees: Int = 0
    /// Épisodes remontés sans resucrage enregistré (remontée spontanée).
    var spontanees: Int = 0
}

/// Snapshot complet d'une nuit prêt à alimenter le graphique d'analyse
/// basale (vues « Toutes » et « Par nuit »). Toutes les valeurs sont
/// pré-calculées par le service — la vue est purement présentationnelle.
nonisolated struct NightChartData: Identifiable, Sendable {
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

    /// Nb d'épisodes hypo (fenêtre de sommeil complète) — source unique des
    /// compteurs. Toujours égal à `bilanHypos.episodes`.
    var hypoCount: Int = 0
    /// Nb de resucrages avec rechute — toujours égal à `bilanHypos.rechutes`.
    var rechuteCount: Int = 0
    /// Taxonomie détaillée des épisodes (série / prolongée / spontanée…) —
    /// consommée par la carte « Verdict de la nuit ».
    var bilanHypos: BilanHyposNuit = BilanHyposNuit()

    /// `true` si cette nuit fait partie des K dernières nuits valides qui
    /// pilotent le verdict global (fenêtre de récence, post-changement de
    /// dose). Renseigné par le calculateur.
    var retenueDansVerdict: Bool = false
    /// Catégorie effective de la nuit dans le verdict (hypo profonde déjà
    /// forcée en tendance basse). `nil` si la nuit n'est pas valide.
    var categorieVerdict: CategorieNuit? = nil
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
