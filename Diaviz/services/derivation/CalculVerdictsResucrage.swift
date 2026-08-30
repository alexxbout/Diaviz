//
//  CalculVerdictsResucrage.swift
//  diaviz
//

import Foundation

// MARK: - Entrées

/// Une prise de glucides à juger — projection value type d'un `Resucrage`,
/// découplée de SwiftData (même pattern qu'`EntreeRatioRepas` pour R1).
nonisolated struct PriseAJuger: Identifiable, Sendable, Equatable {
    let id: String
    let date: Date
    let intention: IntentionResucrage
    let glucides: Int
}

/// Point de glycémie utilisé pour juger — horodatage absolu.
nonisolated struct PointGlycemie: Sendable, Equatable {
    let date: Date
    let valeur: Double
}

/// Bornes de jugement, reprises du profil utilisateur. Aucune convention
/// externe n'entre ici : la zone de référence est celle que l'utilisateur a
/// réglée, cohérente avec le reste de l'app (décision de cadrage S1 —
/// la plage « effort » de la littérature n'est jamais utilisée telle quelle,
/// sa borne haute autoriserait un effort à un niveau que l'app ne doit pas
/// présenter comme acceptable).
nonisolated struct BornesVerdict: Sendable, Equatable {
    let hypoglycemie: Double
    let hyperglycemie: Double
}

// MARK: - Sorties

/// Verdict d'une prise. Toujours descriptif : ce que la glycémie a fait,
/// comparé à ce que l'intention déclarée visait. Jamais une dose à prendre.
nonisolated enum VerdictResucrage: String, Sendable, Equatable {
    /// Correctif : repassé au-dessus du seuil hypo.
    case remonte
    /// Correctif : repassé au-dessus, mais au-delà du seuil hyper —
    /// traiter une hypo ne doit pas créer une hyper.
    case remonteTropHaut
    /// Correctif : toujours sous le seuil hypo en fin de fenêtre.
    case insuffisant
    /// Préventif maintien : resté en cible sur toute la fenêtre.
    case maintenu
    /// Préventif maintien : passé sous le seuil hypo malgré la prise.
    case chuteNonEnrayee
    /// Préventif : monté au-delà du seuil hyper.
    case monteTropHaut
    /// Préventif anti-chute : aucune hypo sur la fenêtre.
    case chuteEvitee
    /// Une autre prise est arrivée avant la fin de la fenêtre : les effets
    /// se mélangent, on ne peut rien attribuer à celle-ci seule.
    case nonEvaluable
    /// Couverture CGM insuffisante sur la fenêtre.
    case indetermine

    var libelle: String {
        switch self {
        case .remonte:          return "Remonté"
        case .remonteTropHaut:  return "Remonté trop haut"
        case .insuffisant:      return "Insuffisant"
        case .maintenu:         return "Maintenu"
        case .chuteNonEnrayee:  return "Chute non enrayée"
        case .monteTropHaut:    return "Monté trop haut"
        case .chuteEvitee:      return "Chute évitée"
        case .nonEvaluable:     return "Non évaluable"
        case .indetermine:      return "Indéterminé"
        }
    }

    /// Tonalité d'affichage — neutre quand rien n'a pu être jugé.
    var tonalite: Tonalite {
        switch self {
        case .remonte, .maintenu, .chuteEvitee:            return .conforme
        case .remonteTropHaut, .monteTropHaut,
             .insuffisant, .chuteNonEnrayee:               return .ecart
        case .nonEvaluable, .indetermine:                  return .neutre
        }
    }

    nonisolated enum Tonalite: Sendable { case conforme, ecart, neutre }
}

/// Pourquoi une prise n'a pas pu être jugée. Les trois cas se ressemblent à
/// l'écran alors qu'ils ne disent pas la même chose — la raison est affichée
/// en clair dans l'encart de détail.
nonisolated enum RaisonNonEvaluable: String, Sendable, Hashable {
    /// Une autre prise de glucides est intervenue avant la fin de la fenêtre.
    case priseSuivante
    /// Une correction d'insuline est intervenue pendant la fenêtre : la
    /// glycémie subit alors deux effets opposés, on ne peut rien attribuer
    /// aux glucides seuls.
    case correctionInsuline
    /// Trop peu de mesures CGM sur la fenêtre.
    case mesuresInsuffisantes

    var libelle: String {
        switch self {
        case .priseSuivante:
            return "un autre resucrage est intervenu pendant la fenêtre"
        case .correctionInsuline:
            return "une correction d'insuline est intervenue pendant la fenêtre"
        case .mesuresInsuffisantes:
            return "pas assez de mesures du capteur sur la fenêtre"
        }
    }
}

/// Tendance de la glycémie juste avant la prise.
nonisolated enum TendanceAvantPrise: String, Sendable, Equatable {
    case baisse, stable, hausse

    var libelle: String {
        switch self {
        case .baisse: return "en baisse"
        case .stable: return "stable"
        case .hausse: return "en hausse"
        }
    }
}

/// Résultat complet pour une prise — tout ce qu'affiche l'encart déplié.
nonisolated struct ResultatPrise: Identifiable, Sendable, Hashable {
    let id: String
    let verdict: VerdictResucrage
    /// Glycémie au moment de la prise. `nil` si aucune mesure exploitable.
    let glycemieAvant: Double?
    /// Glycémie en fin de fenêtre observée.
    let glycemieApres: Double?
    let tendanceAvant: TendanceAvantPrise?
    /// Durée réellement observée, en minutes.
    let dureeFenetreMinutes: Int
    /// Libellé de la fenêtre, pour l'encart (« 30 min après la prise »,
    /// « jusqu'à la fin de l'effort »).
    let libelleFenetre: String
    /// Identifiant de l'épisode auquel la prise appartient — les prises
    /// rapprochées de même intention le partagent.
    let idEpisode: Int
    /// Renseignée uniquement quand le verdict est `nonEvaluable` ou
    /// `indetermine` — explique lequel des cas s'applique.
    var raison: RaisonNonEvaluable? = nil
}

// MARK: - Calculateur

/// Juge chaque prise de glucides d'une séance : la glycémie a-t-elle fait ce
/// que l'intention déclarée visait ?
///
/// **Statistique descriptive pure**, dans la famille de `CalculRatioObserve`
/// et `CalculRepasARevoir` : entrées et sorties en value types, aucun
/// accès SwiftData, aucun modèle entraîné. Chaque verdict est recomptable à
/// la main depuis les points CGM et les seuils du profil.
///
/// ### Fenêtres d'observation
///
/// - **Correctif hypo** et **préventif anti-chute** : 30 min après la prise.
///   Cadence alignée sur le contrôle glycémique recommandé pendant l'effort,
///   et cohérente avec l'action d'un glucide à index élevé.
/// - **Préventif maintien** : jusqu'à la fin de l'effort, plancher à 30 min.
///   Maintenir, c'est tenir jusqu'au bout de la séance — une fenêtre fixe de
///   30 min ne dirait rien d'une course d'une heure. Le plancher évite de
///   juger sur une fenêtre trop courte quand la prise arrive juste avant la
///   fin. Hors séance, on retombe sur les 30 min.
///
/// ### Épisodes
///
/// Deux prises consécutives de **même intention** espacées de moins que le
/// délai de jugement appartiennent au même épisode : si la seconde arrive
/// avant qu'on ait pu juger la première, leurs effets se mélangent. Un
/// changement d'intention ouvre toujours un nouvel épisode, même rapproché —
/// passer de préventif à correctif est une décision différente.
///
/// Une exception à ce silence : quand la prise suivante est un **correctif
/// hypo**, un préventif en cours de fenêtre est jugé `chuteNonEnrayee` plutôt
/// que `nonEvaluable`. Avoir dû traiter une hypo est le résultat du préventif,
/// pas un obstacle à sa lecture.
nonisolated enum CalculVerdictsResucrage {

    /// Délai de jugement de référence, et par construction seuil de
    /// regroupement en épisodes (voir doc du type).
    static let delaiJugement: TimeInterval = 30 * 60

    /// Nombre minimum de mesures sur la fenêtre pour juger — en dessous,
    /// `indetermine` plutôt qu'un verdict sur une courbe trouée.
    static let minimumPoints = 3

    /// Fenêtre de lecture de la tendance précédant la prise.
    private static let fenetreTendance: TimeInterval = 15 * 60

    /// Variation minimale (mg/dL) sur `fenetreTendance` pour ne plus être
    /// considéré comme stable.
    private static let seuilTendance: Double = 10

    // MARK: Point d'entrée

    /// - Parameters:
    ///   - prises: prises à juger, dans n'importe quel ordre.
    ///   - points: mesures CGM couvrant au moins les fenêtres observées.
    ///   - bornes: seuils du profil utilisateur.
    ///   - finEffort: fin de la séance en horloge murale — `nil` hors séance,
    ///     le préventif maintien retombe alors sur le délai de référence.
    ///   - correctionsInsuline: instants des injections rapides. L'app ne juge
    ///     pas ces doses (l'effort fait lui aussi baisser la glycémie, on ne
    ///     saurait pas attribuer), mais leur seule présence dans une fenêtre
    ///     empêche d'y juger les glucides : deux effets opposés s'y mélangent.
    static func juger(
        prises: [PriseAJuger],
        points: [PointGlycemie],
        bornes: BornesVerdict,
        finEffort: Date?,
        correctionsInsuline: [Date] = []
    ) -> [ResultatPrise] {
        let triees = prises.sorted { $0.date < $1.date }
        let mesures = points.sorted { $0.date < $1.date }
        let episodes = decouperEnEpisodes(triees)

        return triees.enumerated().map { index, prise in
            let suivante = triees.indices.contains(index + 1) ? triees[index + 1] : nil
            return juger(
                prise: prise,
                suivante: suivante,
                mesures: mesures,
                bornes: bornes,
                finEffort: finEffort,
                correctionsInsuline: correctionsInsuline,
                idEpisode: episodes[prise.id] ?? 0
            )
        }
    }

    // MARK: Épisodes

    /// Associe à chaque prise l'identifiant de son épisode.
    static func decouperEnEpisodes(_ prises: [PriseAJuger]) -> [String: Int] {
        var parPrise: [String: Int] = [:]
        var episode = 0
        var precedente: PriseAJuger?

        for prise in prises {
            if let precedente {
                let ecart = prise.date.timeIntervalSince(precedente.date)
                let memeIntention = prise.intention == precedente.intention
                if !memeIntention || ecart >= delaiJugement {
                    episode += 1
                }
            }
            parPrise[prise.id] = episode
            precedente = prise
        }
        return parPrise
    }

    // MARK: Jugement d'une prise

    private static func juger(
        prise: PriseAJuger,
        suivante: PriseAJuger?,
        mesures: [PointGlycemie],
        bornes: BornesVerdict,
        finEffort: Date?,
        correctionsInsuline: [Date],
        idEpisode: Int
    ) -> ResultatPrise {
        let (fin, libelleFenetre) = fenetre(pour: prise, finEffort: finEffort)
        let dureeMinutes = Int(fin.timeIntervalSince(prise.date) / 60)

        // Priorité sur toutes les autres invalidations : une injection dans la
        // fenêtre pousse la glycémie dans le sens opposé aux glucides. Même
        // l'échec apparent d'un préventif deviendrait ininterprétable — ce
        // serait peut-être l'insuline qui a fait chuter, pas la dose de
        // glucides qui était insuffisante.
        if correctionsInsuline.contains(where: { $0 > prise.date && $0 < fin }) {
            return ResultatPrise(
                id: prise.id,
                verdict: .nonEvaluable,
                glycemieAvant: valeur(a: prise.date, dans: mesures),
                glycemieApres: nil,
                tendanceAvant: tendance(avant: prise.date, dans: mesures),
                dureeFenetreMinutes: dureeMinutes,
                libelleFenetre: libelleFenetre,
                idEpisode: idEpisode,
                raison: .correctionInsuline
            )
        }

        if let suivante, suivante.date < fin {
            // Devoir traiter une hypo pendant la fenêtre d'un préventif est en
            // soi le résultat : la prise n'a pas tenu son objectif. C'est
            // l'information la plus utile de la séance, on ne la jette pas
            // derrière un « non évaluable ».
            let echecPreventif = prise.intention != .correctifHypo
                && suivante.intention == .correctifHypo

            return ResultatPrise(
                id: prise.id,
                verdict: echecPreventif ? .chuteNonEnrayee : .nonEvaluable,
                glycemieAvant: valeur(a: prise.date, dans: mesures),
                glycemieApres: echecPreventif
                    ? valeur(a: suivante.date, dans: mesures)
                    : nil,
                tendanceAvant: tendance(avant: prise.date, dans: mesures),
                dureeFenetreMinutes: echecPreventif
                    ? Int(suivante.date.timeIntervalSince(prise.date) / 60)
                    : dureeMinutes,
                libelleFenetre: echecPreventif
                    ? "jusqu'au resucrage suivant"
                    : libelleFenetre,
                idEpisode: idEpisode,
                raison: echecPreventif ? nil : .priseSuivante
            )
        }

        let surFenetre = mesures.filter { $0.date >= prise.date && $0.date <= fin }
        guard surFenetre.count >= minimumPoints,
              let avant = valeur(a: prise.date, dans: mesures),
              let apres = surFenetre.last?.valeur
        else {
            return ResultatPrise(
                id: prise.id,
                verdict: .indetermine,
                glycemieAvant: valeur(a: prise.date, dans: mesures),
                glycemieApres: nil,
                tendanceAvant: tendance(avant: prise.date, dans: mesures),
                dureeFenetreMinutes: dureeMinutes,
                libelleFenetre: libelleFenetre,
                idEpisode: idEpisode,
                raison: .mesuresInsuffisantes
            )
        }

        let minimum = surFenetre.map(\.valeur).min() ?? apres
        let maximum = surFenetre.map(\.valeur).max() ?? apres

        return ResultatPrise(
            id: prise.id,
            verdict: verdict(
                intention: prise.intention,
                apres: apres,
                minimum: minimum,
                maximum: maximum,
                bornes: bornes
            ),
            glycemieAvant: avant,
            glycemieApres: apres,
            tendanceAvant: tendance(avant: prise.date, dans: mesures),
            dureeFenetreMinutes: dureeMinutes,
            libelleFenetre: libelleFenetre,
            idEpisode: idEpisode
        )
    }

    /// Verdict selon l'intention déclarée — c'est elle qui définit ce que
    /// « réussi » veut dire, d'où son caractère obligatoire à la saisie.
    private static func verdict(
        intention: IntentionResucrage,
        apres: Double,
        minimum: Double,
        maximum: Double,
        bornes: BornesVerdict
    ) -> VerdictResucrage {
        switch intention {
        case .correctifHypo:
            if apres < bornes.hypoglycemie { return .insuffisant }
            if maximum > bornes.hyperglycemie { return .remonteTropHaut }
            return .remonte

        case .preventifMaintien:
            if minimum < bornes.hypoglycemie { return .chuteNonEnrayee }
            if maximum > bornes.hyperglycemie { return .monteTropHaut }
            return .maintenu

        case .preventifAntiChute:
            if minimum < bornes.hypoglycemie { return .chuteNonEnrayee }
            if maximum > bornes.hyperglycemie { return .monteTropHaut }
            return .chuteEvitee
        }
    }

    // MARK: Fenêtre

    private static func fenetre(
        pour prise: PriseAJuger,
        finEffort: Date?
    ) -> (fin: Date, libelle: String) {
        let parDefaut = prise.date.addingTimeInterval(delaiJugement)
        guard prise.intention == .preventifMaintien, let finEffort else {
            return (parDefaut, "30 min après la prise")
        }
        // Plancher : une prise juste avant la fin ne se juge pas sur 3 min.
        guard finEffort > parDefaut else {
            return (parDefaut, "30 min après la prise")
        }
        return (finEffort, "jusqu'à la fin de l'effort")
    }

    // MARK: Lecture des mesures

    /// Mesure la plus proche d'un instant, dans une tolérance de 10 min.
    private static func valeur(a instant: Date, dans mesures: [PointGlycemie]) -> Double? {
        let proche = mesures.min {
            abs($0.date.timeIntervalSince(instant)) < abs($1.date.timeIntervalSince(instant))
        }
        guard let proche,
              abs(proche.date.timeIntervalSince(instant)) <= 10 * 60 else { return nil }
        return proche.valeur
    }

    private static func tendance(
        avant instant: Date,
        dans mesures: [PointGlycemie]
    ) -> TendanceAvantPrise? {
        let debut = instant.addingTimeInterval(-fenetreTendance)
        let surFenetre = mesures.filter { $0.date >= debut && $0.date <= instant }
        guard let premiere = surFenetre.first, let derniere = surFenetre.last,
              surFenetre.count >= 2 else { return nil }
        let delta = derniere.valeur - premiere.valeur
        if delta <= -seuilTendance { return .baisse }
        if delta >= seuilTendance { return .hausse }
        return .stable
    }
}
