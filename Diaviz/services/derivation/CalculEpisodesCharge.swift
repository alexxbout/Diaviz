//
//  CalculEpisodesCharge.swift
//  diaviz
//

import Foundation

// MARK: - Entrées

/// Moment de repas d'un ratio — `unique` en mode ratio unique. Le goûter
/// correspond à la section « En-cas », la nuit retombe sur le soir (même
/// repli que `InsightsService.ratioConfigure`).
nonisolated enum MomentRatio: String, Sendable, CaseIterable {
    case unique, matin, midi, gouter, soir

    var libelle: String {
        switch self {
        case .unique: "Ratio"
        case .matin:  "Ratio matin"
        case .midi:   "Ratio midi"
        case .gouter: "Ratio goûter"
        case .soir:   "Ratio soir"
        }
    }
}

/// Un réglage dont l'état est suivi par épisode (C1 § 6). Le facteur de
/// correction est hors V1 (C1 § 7).
nonisolated enum ReglageSuivi: Hashable, Sendable {
    case lente
    case ratio(MomentRatio)
    /// Ratio post-effort d'un type de sport (`TypeSport.rawValue`).
    case ratioSport(String)

    var regle: RegleEtatReglage {
        switch self {
        case .lente:      .lente
        case .ratio:      .ratioRepas
        case .ratioSport: .ratioSport
        }
    }

    /// Ordre d'affichage stable : lente, ratios dans l'ordre de la journée,
    /// puis sports.
    var rangAffichage: Int {
        switch self {
        case .lente:            0
        case .ratio(let m):     1 + (MomentRatio.allCases.firstIndex(of: m) ?? 0)
        case .ratioSport:       10
        }
    }
}

/// Ce qu'un événement (une nuit, un repas) dit du réglage en vigueur.
nonisolated enum IssueEvenement: Sendable, Hashable {
    case concluant
    /// Raté sans hypo (dérive, pic hors cible).
    case rate
    /// Raté par une hypo — compte pour le garde-fou (C1 § 6).
    case hypo
    /// Ni concluant ni raté : exclu par B1 ou R1, verdict `moyen`, hypo
    /// expliquée par l'insuline rapide active…
    case nonEvaluable
}

/// Un événement jugé : une nuit pour la lente, un repas pour un ratio.
/// `valeur` = valeur du réglage en vigueur à ce moment, `nil` si elle n'est
/// pas connue (ratio antérieur à l'enregistreur d'historique).
nonisolated struct EvenementReglage: Sendable, Equatable {
    let date: Date
    let reglage: ReglageSuivi
    let valeur: Double?
    let issue: IssueEvenement
}

/// Glycémie CGM, pour les résultats d'un épisode.
nonisolated struct MesureGlycemie: Sendable, Equatable {
    let date: Date
    let valeur: Int
}

// MARK: - Règles (registre : docs/architecture/Diaviz — Paramètres à calibrer.md)

/// Seuils d'état propres à un réglage, en comptes (C1 § 6-7).
nonisolated struct RegleEtatReglage: Sendable, Equatable {
    /// Taille de la fenêtre glissante d'événements évaluables.
    let fenetre: Int
    /// Événements évaluables requis avant tout verdict.
    let minimum: Int
    /// Concluants requis dans la fenêtre pour devenir concluant.
    let entree: Int
    /// À ce compte de concluants ou moins, un réglage concluant repasse en
    /// ajustement.
    let sortie: Int
    /// Événements ignorés après un changement de valeur (lente seulement).
    let transition: Int

    static let lente = RegleEtatReglage(fenetre: 7, minimum: 5, entree: 5, sortie: 3, transition: 2)
    static let ratioRepas = RegleEtatReglage(fenetre: 8, minimum: 5, entree: 5, sortie: 3, transition: 0)
    static let ratioSport = RegleEtatReglage(fenetre: 6, minimum: 4, entree: 4, sortie: 2, transition: 0)

    /// Garde-fou hypo commun : à partir de ce nombre d'hypos dans la
    /// fenêtre, jamais concluant (C1 § 6, « Garde-fou hypo »).
    static let hyposBloquantes = 2
}

// MARK: - Résultat

/// État d'un réglage à la fin d'une plage d'événements.
nonisolated enum EtatReglage: Sendable, Equatable {
    case pasAssezDeRecul(evaluables: Int, requis: Int)
    /// Nouvelle dose de lente, dans ses nuits de transition.
    case observation(faites: Int, sur: Int)
    case ajustement(concluants: Int, fenetre: Int, hypos: Int)
    case concluant(concluants: Int, fenetre: Int, hypos: Int)
}

/// Un événement tel qu'affiché dans le détail d'un réglage (pastilles).
nonisolated struct EvenementAffiche: Sendable, Equatable, Identifiable {
    let date: Date
    let issue: IssueEvenement
    /// Dans les événements de transition qui suivent un changement de valeur.
    let enObservation: Bool
    var id: Date { date }
}

/// Usage d'une valeur d'un réglage pendant un épisode.
nonisolated struct UsageValeur: Sendable, Equatable {
    let valeur: Double?
    let concluants: Int
    let evaluables: Int
    let hypos: Int
    /// La valeur a été concluante au moins une fois pendant l'épisode.
    let aEteConcluante: Bool
    /// Date du dernier événement — départage les égalités.
    let dernier: Date
    /// Moins d'événements évaluables que le minimum du réglage.
    let tropCourt: Bool
}

/// Ce qu'un épisode retient d'un réglage (C1 § 8).
nonisolated enum ValeurRetenue: Sendable, Equatable {
    /// La valeur la plus concluante parmi celles qui ont rempli les critères.
    case concluante(UsageValeur)
    /// Aucune valeur n'a rempli les critères ; `derniere` = dernière appliquée.
    case aucune(derniere: Double?)
    case pasAssezDeRecul
}

nonisolated struct ReglageEpisode: Sendable, Equatable {
    let reglage: ReglageSuivi
    let retenue: ValeurRetenue
    /// Toutes les valeurs utilisées pendant l'épisode, chronologiques.
    let usages: [UsageValeur]
}

/// Charge réelle d'un épisode, en faits.
nonisolated struct FaitsEpisode: Sendable, Equatable {
    let jours: Int
    let seancesParSemaine: Double
    let minutesSeancesParSemaine: Double
    let minutesMarcheParSemaine: Double
}

/// Résultats d'un épisode, tous réglages confondus (C1 § 8). `nil` sous le
/// seuil de lisibilité de la métrique.
nonisolated struct ResultatsEpisode: Sendable, Equatable {
    let tempsDansLaCible: Double?
    let scoreMoyen: Double?
    let resucragesParJour: Double?
    /// Qualité de la donnée, toujours renseignée dès qu'un jour existe.
    let couvertureCGM: Double?
}

nonisolated struct EpisodeCharge: Sendable, Equatable, Identifiable {
    /// Début du premier jour.
    let debut: Date
    /// Début du dernier jour.
    let dernierJour: Date
    let enCours: Bool
    /// `nil` = sans référence (moins de 5 semaines d'historique).
    let niveau: NiveauChargeActive?
    let faits: FaitsEpisode
    /// Moyenne du stock de charge active sur l'épisode, en unité absolue.
    /// Sert à comparer les épisodes entre eux ; jamais affichée.
    let chargeMoyenne: Double
    let reglages: [ReglageEpisode]
    let resultats: ResultatsEpisode

    var id: Date { debut }
}

/// État courant d'un réglage, pour la page (écran 1).
nonisolated struct EtatReglageActuel: Sendable, Equatable, Identifiable {
    let reglage: ReglageSuivi
    /// Valeur actuelle (profil ou dernière injection).
    let valeur: Double?
    let etat: EtatReglage
    /// Date et ancienne valeur du dernier changement, s'il a eu lieu dans
    /// l'épisode en cours.
    let changement: (date: Date, ancienne: Double?)?
    /// Événements de l'épisode en cours à la valeur actuelle.
    let evenements: [EvenementAffiche]
    /// Premier événement à la valeur actuelle, `nil` sans événement.
    var depuis: Date? = nil

    var id: Int { reglage.hashValue }

    static func == (a: EtatReglageActuel, b: EtatReglageActuel) -> Bool {
        a.reglage == b.reglage && a.valeur == b.valeur && a.etat == b.etat
            && a.changement?.date == b.changement?.date && a.changement?.ancienne == b.changement?.ancienne
            && a.evenements == b.evenements && a.depuis == b.depuis
    }
}

nonisolated struct SyntheseEpisodesCharge: Sendable, Equatable {
    let enCours: EpisodeCharge?
    /// Épisode juste avant celui en cours.
    let precedent: EpisodeCharge?
    /// Épisodes passés à charge réelle comparable, plus récent d'abord.
    let comparables: [EpisodeCharge]
    /// Les autres épisodes passés, plus récent d'abord.
    let autres: [EpisodeCharge]
    let etatsActuels: [EtatReglageActuel]

    static let vide = SyntheseEpisodesCharge(enCours: nil, precedent: nil, comparables: [], autres: [], etatsActuels: [])

    var episodesPasses: [EpisodeCharge] { (comparables + autres).sorted { $0.debut > $1.debut } }
}

// MARK: - Calculateur

/// **Épisodes de charge** (C1) : découpe l'historique en épisodes de même
/// niveau de charge active, juge chaque réglage sur ses propres événements
/// et retrouve les épisodes passés à charge réelle comparable.
/// Descriptif strict : aucune suggestion de dose, aucun classement.
/// Doc canonique : `docs/analyses/C1 — Frise des périodes.md`.
nonisolated enum CalculEpisodesCharge {

    /// Écart relatif de charge moyenne sous lequel deux épisodes sont
    /// comparables (C1 § 5).
    static let ecartChargeComparable = 0.30
    /// Durée d'affichage du badge « Nouvel épisode ».
    static let joursNouvelEpisode = 7
    /// Seuils de lisibilité des résultats d'épisode.
    static let joursMinimumNiveauGlycemie = 3
    static let joursMinimumResucrages = 7

    static func analyser(
        charge: ContexteChargeActive,
        evenements: [EvenementReglage],
        valeursActuelles: [ReglageSuivi: Double],
        glycemies: [MesureGlycemie],
        resucrages: [Date],
        maintenant: Date = Date()
    ) -> SyntheseEpisodesCharge {
        let cal = charge.calendrier
        let jours = charge.jours.filter { $0.jour <= maintenant }
        guard !jours.isEmpty else { return .vide }

        let parReglage = Dictionary(grouping: evenements, by: \.reglage)
            .mapValues { $0.sorted { $0.date < $1.date } }
        let segmentsParReglage = parReglage.mapValues(segmenter)

        let bornes = decouper(jours)
        let finPlage = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: maintenant)) ?? maintenant

        let episodes: [EpisodeCharge] = bornes.enumerated().map { index, plage in
            let estDernier = index == bornes.count - 1
            let debut = plage.jours.first?.jour ?? maintenant
            let dernierJour = plage.jours.last?.jour ?? maintenant
            let fin = estDernier ? min(finPlage, maintenant) : (cal.date(byAdding: .day, value: 1, to: dernierJour) ?? dernierJour)
            let reglages = segmentsParReglage.keys
                .sorted { $0.rangAffichage < $1.rangAffichage }
                .compactMap { reglage -> ReglageEpisode? in
                    let usages = usagesDansPlage(segmentsParReglage[reglage] ?? [], debut: debut, fin: fin, regle: reglage.regle)
                    guard !usages.isEmpty else { return nil }
                    return ReglageEpisode(reglage: reglage, retenue: retenir(usages), usages: usages)
                }
            return EpisodeCharge(
                debut: debut,
                dernierJour: dernierJour,
                enCours: estDernier,
                niveau: plage.niveau,
                faits: faits(plage.jours),
                chargeMoyenne: CalculChargeActive.moyenneChargeActive(de: debut, a: fin, contributions: charge.contributions),
                reglages: reglages,
                resultats: resultats(
                    debut: debut, fin: fin, jours: plage.jours.count,
                    glycemies: glycemies, resucrages: resucrages, calendrier: cal
                )
            )
        }

        guard let enCours = episodes.last else { return .vide }
        let passes = Array(episodes.dropLast()).reversed()
        let comparables = passes.filter { estComparable($0, a: enCours) }
        let autres = passes.filter { !estComparable($0, a: enCours) }

        let reglagesActuels = Set(segmentsParReglage.keys).union(valeursActuelles.keys)
            .sorted { $0.rangAffichage < $1.rangAffichage }
        let etats = reglagesActuels.map { reglage in
            etatActuel(
                reglage: reglage,
                segments: segmentsParReglage[reglage] ?? [],
                valeurActuelle: valeursActuelles[reglage],
                debutEpisode: enCours.debut
            )
        }

        return SyntheseEpisodesCharge(
            enCours: enCours,
            precedent: passes.first,
            comparables: Array(comparables),
            autres: Array(autres),
            etatsActuels: etats
        )
    }

    // MARK: Épisodes

    struct Plage {
        let niveau: NiveauChargeActive?
        var jours: [JourChargeActive]
    }

    /// Suites de jours consécutifs au même niveau (`nil` compris).
    static func decouper(_ jours: [JourChargeActive]) -> [Plage] {
        var plages: [Plage] = []
        for jour in jours {
            if let derniere = plages.last, derniere.niveau == jour.niveau {
                plages[plages.count - 1].jours.append(jour)
            } else {
                plages.append(Plage(niveau: jour.niveau, jours: [jour]))
            }
        }
        return plages
    }

    static func faits(_ jours: [JourChargeActive]) -> FaitsEpisode {
        let semaines = max(Double(jours.count), 1) / 7
        return FaitsEpisode(
            jours: jours.count,
            seancesParSemaine: Double(jours.reduce(0) { $0 + $1.nombreSeances }) / semaines,
            minutesSeancesParSemaine: jours.reduce(0) { $0 + $1.minutesSeances } / semaines,
            minutesMarcheParSemaine: jours.reduce(0) { $0 + $1.minutesMarche } / semaines
        )
    }

    static func estComparable(_ episode: EpisodeCharge, a reference: EpisodeCharge) -> Bool {
        guard reference.chargeMoyenne > 0 else { return episode.chargeMoyenne == 0 }
        return abs(episode.chargeMoyenne - reference.chargeMoyenne) / reference.chargeMoyenne <= ecartChargeComparable
    }

    static func resultats(
        debut: Date, fin: Date, jours: Int,
        glycemies: [MesureGlycemie], resucrages: [Date], calendrier: Calendar
    ) -> ResultatsEpisode {
        let mesures = glycemies.filter { $0.date >= debut && $0.date < fin }
        let joursCouverts = Set(mesures.map { calendrier.startOfDay(for: $0.date) }).count
        let attendues = max(fin.timeIntervalSince(debut) / 300, 1)
        let couverture = jours > 0 ? min(100, Double(mesures.count) / attendues * 100) : nil
        let lisible = joursCouverts >= joursMinimumNiveauGlycemie
        let valeurs = mesures.map { (date: $0.date, valeur: $0.valeur) }
        let nombreResucrages = resucrages.filter { $0 >= debut && $0 < fin }.count
        return ResultatsEpisode(
            tempsDansLaCible: lisible ? CalculCorrelationChargeTIR.tir(valeurs) : nil,
            scoreMoyen: lisible ? CalculCorrelationChargeTIR.scoreGRI(mesures: valeurs) : nil,
            resucragesParJour: jours >= joursMinimumResucrages ? Double(nombreResucrages) / Double(jours) : nil,
            couvertureCGM: couverture
        )
    }

    // MARK: Segments de valeur

    /// Événement daté dans son segment, avec sa place après le changement.
    struct EvenementMarque {
        let evenement: EvenementReglage
        let enObservation: Bool
    }

    struct Segment {
        let valeur: Double?
        /// Valeur du segment précédent ; absent pour le tout premier.
        let ancienne: Double??
        let debut: Date
        var evenements: [EvenementMarque]
        var estPremier: Bool { ancienne == nil }
    }

    /// Suites d'événements à valeur constante. Les premiers événements d'un
    /// segment qui suit un changement sont marqués en observation selon la
    /// transition du réglage — jamais le tout premier segment, dont le début
    /// n'est pas un changement.
    static func segmenter(_ evenements: [EvenementReglage]) -> [Segment] {
        var segments: [Segment] = []
        for e in evenements {
            if let dernier = segments.last, dernier.valeur == e.valeur {
                let rang = dernier.evenements.count
                let observe = !dernier.estPremier && rang < e.reglage.regle.transition
                segments[segments.count - 1].evenements.append(EvenementMarque(evenement: e, enObservation: observe))
            } else {
                var ancienne: Double?? = nil
                if let precedent = segments.last { ancienne = .some(precedent.valeur) }
                let observe = ancienne != nil && e.reglage.regle.transition > 0
                segments.append(Segment(
                    valeur: e.valeur, ancienne: ancienne, debut: e.date,
                    evenements: [EvenementMarque(evenement: e, enObservation: observe)]
                ))
            }
        }
        return segments
    }

    // MARK: États

    /// Rejoue l'état d'un réglage événement par événement, avec hystérésis.
    /// Retourne l'état final et si l'état concluant a été atteint.
    static func rejouer(_ evenements: [EvenementMarque], regle: RegleEtatReglage) -> (etat: EtatReglage, aEteConcluant: Bool) {
        let evaluables = evenements.filter { !$0.enObservation && $0.evenement.issue != .nonEvaluable }.map(\.evenement.issue)
        guard evaluables.count >= regle.minimum else {
            return (.pasAssezDeRecul(evaluables: evaluables.count, requis: regle.minimum), false)
        }
        var concluant = false
        var aEteConcluant = false
        var dernier = (concluants: 0, fenetre: 0, hypos: 0)
        for fin in regle.minimum...evaluables.count {
            let fenetre = evaluables[max(0, fin - regle.fenetre)..<fin]
            let c = fenetre.filter { $0 == .concluant }.count
            let h = fenetre.filter { $0 == .hypo }.count
            dernier = (c, fenetre.count, h)
            if h >= RegleEtatReglage.hyposBloquantes {
                concluant = false
            } else if concluant {
                if c <= regle.sortie { concluant = false }
            } else if c >= regle.entree {
                concluant = true
            }
            aEteConcluant = aEteConcluant || concluant
        }
        let etat: EtatReglage = concluant
            ? .concluant(concluants: dernier.concluants, fenetre: dernier.fenetre, hypos: dernier.hypos)
            : .ajustement(concluants: dernier.concluants, fenetre: dernier.fenetre, hypos: dernier.hypos)
        return (etat, aEteConcluant)
    }

    /// Usages de chaque valeur dans `[debut, fin[`. Les événements d'un
    /// segment sont rejoués à partir du début de la plage : un épisode
    /// repart toujours de zéro (C1 § 6).
    static func usagesDansPlage(_ segments: [Segment], debut: Date, fin: Date, regle: RegleEtatReglage) -> [UsageValeur] {
        segments.compactMap { segment in
            let dedans = segment.evenements.filter { $0.evenement.date >= debut && $0.evenement.date < fin }
            guard let dernier = dedans.last else { return nil }
            let evaluables = dedans.filter { !$0.enObservation && $0.evenement.issue != .nonEvaluable }
            let (_, aEteConcluant) = rejouer(dedans, regle: regle)
            return UsageValeur(
                valeur: segment.valeur,
                concluants: evaluables.filter { $0.evenement.issue == .concluant }.count,
                evaluables: evaluables.count,
                hypos: evaluables.filter { $0.evenement.issue == .hypo }.count,
                aEteConcluante: aEteConcluant,
                dernier: dernier.evenement.date,
                tropCourt: evaluables.count < regle.minimum
            )
        }
    }

    /// Valeur la plus concluante (compte de concluants, égalité : la plus
    /// récente), parmi celles qui ont rempli les critères. Une même valeur
    /// reprise plus tard dans l'épisode garde ses usages séparés.
    static func retenir(_ usages: [UsageValeur]) -> ValeurRetenue {
        let candidates = usages.filter(\.aEteConcluante)
        if let meilleure = candidates.max(by: { ($0.concluants, $0.dernier) < ($1.concluants, $1.dernier) }) {
            return .concluante(meilleure)
        }
        if usages.allSatisfy(\.tropCourt) { return .pasAssezDeRecul }
        return .aucune(derniere: usages.last?.valeur)
    }

    static func etatActuel(
        reglage: ReglageSuivi,
        segments: [Segment],
        valeurActuelle: Double?,
        debutEpisode: Date
    ) -> EtatReglageActuel {
        let regle = reglage.regle
        let dernier = segments.last
        // Valeur changée depuis le dernier événement (aujourd'hui, sans nuit
        // ni repas encore) : nouveau segment vide.
        if let valeurActuelle, let dernier, dernier.valeur != valeurActuelle {
            let etat: EtatReglage = regle.transition > 0
                ? .observation(faites: 0, sur: regle.transition)
                : .pasAssezDeRecul(evaluables: 0, requis: regle.minimum)
            return EtatReglageActuel(
                reglage: reglage, valeur: valeurActuelle, etat: etat,
                changement: nil, evenements: []
            )
        }
        guard let dernier else {
            return EtatReglageActuel(
                reglage: reglage, valeur: valeurActuelle,
                etat: .pasAssezDeRecul(evaluables: 0, requis: regle.minimum),
                changement: nil, evenements: []
            )
        }
        let dansEpisode = dernier.evenements.filter { $0.evenement.date >= debutEpisode }
        let observes = dernier.evenements.filter(\.enObservation).count
        let enTransition = !dernier.estPremier && dernier.evenements.count <= regle.transition
            && dernier.evenements.allSatisfy(\.enObservation)
        let etat: EtatReglage = enTransition
            ? .observation(faites: observes, sur: regle.transition)
            : rejouer(dansEpisode, regle: regle).etat
        var changement: (date: Date, ancienne: Double?)?
        if case .some(let ancienne) = dernier.ancienne, dernier.debut >= debutEpisode {
            changement = (dernier.debut, ancienne)
        }
        return EtatReglageActuel(
            reglage: reglage,
            valeur: valeurActuelle ?? dernier.valeur,
            etat: etat,
            changement: changement,
            evenements: dansEpisode.map {
                EvenementAffiche(date: $0.evenement.date, issue: $0.evenement.issue, enObservation: $0.enObservation)
            },
            depuis: dernier.debut
        )
    }
}
