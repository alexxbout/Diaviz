//
//  CalculChargeActive.swift
//  diaviz
//

import Foundation

// MARK: - Entrées

/// Séance enregistrée, réduite à ce qui compte pour la charge active.
/// Hub (`ActiviteSportive`) enrichi, pour les séances importées, du workout
/// Apple Santé correspondant (type d'activité, FC moyenne lue à la volée).
nonisolated struct SeancePourCharge: Sendable {
    let debut: Date
    let dureeMin: Int
    let intensite: IntensiteSport
    /// FC moyenne de la séance (bpm) — `nil` si aucun échantillon cardio.
    let fcMoyenne: Double?
    /// `HKWorkoutActivityType.rawValue` quand la séance vient d'Apple Santé.
    /// Capté mais sans effet tant que `coefficientType` vaut 1 partout.
    let typeActiviteHK: UInt?

    var fin: Date { debut.addingTimeInterval(Double(dureeMin) * 60) }
}

/// Nombre de pas d'une minute calendaire (bucket de statistiques HealthKit).
nonisolated struct PasMinute: Sendable, Equatable {
    let debut: Date
    let pas: Double
}

/// Nombre de pas d'une heure calendaire — sert uniquement au préfiltrage des
/// plages à relire à la minute (`plagesCandidates`).
nonisolated struct PasHeure: Sendable, Equatable {
    let debut: Date
    let pas: Double
}

/// Bout de marche soutenue détecté dans les pas (hors séance enregistrée).
nonisolated struct BoutMarche: Sendable, Equatable {
    let debut: Date
    let fin: Date
    let pas: Double

    var dureeMin: Double { fin.timeIntervalSince(debut) / 60 }
}

/// Apport élémentaire au stock : `charge` réalisée à `instant` (fin de la
/// séance ou du bout de marche), puis décroissance exponentielle.
nonisolated struct ContributionCharge: Sendable, Equatable {
    enum Source: Sendable, Equatable { case seance, marche }
    let instant: Date
    let charge: Double
    let source: Source
}

// MARK: - Résultat

nonisolated enum NiveauChargeActive: Sendable, Equatable {
    case basse, normale, haute

    var libelle: String {
        switch self {
        case .basse:   "Charge active basse"
        case .normale: "Charge active normale"
        case .haute:   "Charge active haute"
        }
    }
}

nonisolated enum EtatChargeActive: Sendable, Equatable {
    /// Historique plus court que la fenêtre de référence — pas de normale.
    case pasAssezDeRecul
    /// Ni séance ni marche soutenue sur la fenêtre de référence : la normale
    /// est nulle, un rapport n'a pas de sens (et « charge basse » serait un
    /// faux constat).
    case aucuneActiviteDeReference
    /// `indice` = charge active maintenant / normale personnelle.
    /// `depuisJours` = jours depuis la dernière bascule de niveau observée
    /// dans la série, `nil` si aucune bascule sur la série.
    case disponible(indice: Double, niveau: NiveauChargeActive, depuisJours: Int?)
}

nonisolated struct SyntheseChargeActive: Sendable, Equatable {
    let etat: EtatChargeActive
    /// `false` quand les pas n'ont pas pu être lus (autorisation Santé
    /// refusée ou aucun pas enregistré) : charge sur les séances seules,
    /// à signaler comme partielle.
    let marcheIncluse: Bool
}

// MARK: - Calculateur

/// **Charge active** — ce qui reste de sensibilité gagnée par les séances
/// passées. Évolution de `CalculChargeContinue` (dont elle reprend facteurs
/// d'intensité, seuil ±40 % et minimum de jours) : au lieu de cloisonner la
/// charge par jour puis de la sommer par semaine, chaque séance alimente un
/// stock qui décroît de façon exponentielle (demi-vie 24 h). Même forme que
/// `IOBCalculateur`, sans pic différé.
///
///     charge_active(T) = Σ charge_i · exp(−ln2 / demi_vie · (T − t_i))
///
/// Dérivation pure, jamais persistée. Doc canonique :
/// `docs/architecture/Diaviz — Charge active (sport).md`.
///
/// **Normale dans la même unité.** L'indice rapporte le stock actuel à la
/// **moyenne temporelle du stock** sur la fenêtre de référence — pas à la
/// somme hebdomadaire de `CalculChargeContinue`. En régime établi, la
/// moyenne du stock vaut `charge_journalière × τ` avec `τ = demi_vie / ln2`
/// ≈ 1,44 j : diviser par la somme hebdo / 7 ferait sortir un indice de 1,44
/// pour une semaine parfaitement habituelle.
nonisolated enum CalculChargeActive {

    // MARK: Paramètres (registre : docs/architecture/Diaviz — Paramètres à calibrer.md)

    static let demiVieHeures = 24.0
    /// Fenêtre de la normale : 4 semaines, se terminant `exclusionRecenteJours`
    /// avant maintenant — même logique que `CalculChargeContinue` (S-1 à S-4),
    /// pour que la normale ne suive pas la variation qu'elle doit révéler.
    static let fenetreNormaleJours = 28
    static let exclusionRecenteJours = 7
    /// Jours de niveau rejoués pour l'hystérésis — l'état de départ est
    /// supposé normal, il a le temps de converger sur cette durée.
    static let joursSerieNiveau = 28
    /// Marge avant la plus ancienne fenêtre : ~5 demi-vies, au-delà desquelles
    /// une séance ne pèse plus que ~3 % de sa charge.
    static let margeDecroissanceJours = 7

    static let cadenceMarcheMin = 100.0
    static let dureeMarcheMinMinutes = 10
    static let coefficientMarche = 0.75

    /// FC max théorique — même valeur que `intensiteDepuisFC`.
    static let fcMaxTheorique = 190.0

    /// Profondeur d'historique totale à charger pour `analyser`.
    static var profondeurJours: Int {
        joursSerieNiveau + fenetreNormaleJours + exclusionRecenteJours + margeDecroissanceJours
    }

    static var lambdaParSeconde: Double { log(2) / (demiVieHeures * 3600) }

    // MARK: Pondération

    /// Coefficient par famille d'activité — 1 partout tant qu'aucune donnée
    /// ne justifie de différencier (doc § 5). Le type est capté pour plus tard.
    static func coefficientType(_ typeActiviteHK: UInt?) -> Double { 1.0 }

    /// Facteur d'intensité : FC moyenne si disponible, interpolée en continu
    /// sur les mêmes zones que `intensiteDepuisFC` (50 % FCmax → 1, 70 % → 2,
    /// 90 % → 3, borné à [1, 3]) ; sinon l'intensité saisie
    /// (`CalculChargeContinue.facteur`).
    static func facteurIntensite(_ seance: SeancePourCharge) -> Double {
        guard let fc = seance.fcMoyenne, fc > 0 else {
            return CalculChargeContinue.facteur(seance.intensite)
        }
        let pourcentage = fc / fcMaxTheorique
        return min(3, max(1, 1 + (pourcentage - 0.5) / 0.2))
    }

    static func charge(_ seance: SeancePourCharge) -> Double {
        coefficientType(seance.typeActiviteHK) * facteurIntensite(seance) * Double(seance.dureeMin)
    }

    /// Un bout de marche pèse comme une séance faible (facteur 1), réduite
    /// par `coefficientMarche`.
    static func charge(_ bout: BoutMarche) -> Double {
        coefficientMarche * CalculChargeContinue.facteur(.faible) * bout.dureeMin
    }

    // MARK: Décroissance

    /// Stock à l'instant `instant` — seuls les apports passés comptent.
    static func chargeActive(a instant: Date, contributions: [ContributionCharge]) -> Double {
        let lambda = lambdaParSeconde
        return contributions.reduce(0.0) { total, c in
            let dt = instant.timeIntervalSince(c.instant)
            guard dt >= 0 else { return total }
            return total + c.charge * exp(-lambda * dt)
        }
    }

    /// Moyenne temporelle exacte du stock sur `[debut, fin]` (intégrale
    /// analytique de chaque exponentielle, pas d'échantillonnage).
    static func moyenneChargeActive(de debut: Date, a fin: Date, contributions: [ContributionCharge]) -> Double {
        let duree = fin.timeIntervalSince(debut)
        guard duree > 0 else { return chargeActive(a: fin, contributions: contributions) }
        let lambda = lambdaParSeconde
        let integrale = contributions.reduce(0.0) { total, c in
            guard c.instant < fin else { return total }
            let depart = max(debut, c.instant)
            let a = depart.timeIntervalSince(c.instant)
            let b = fin.timeIntervalSince(c.instant)
            return total + c.charge / lambda * (exp(-lambda * a) - exp(-lambda * b))
        }
        return integrale / duree
    }

    /// Normale personnelle à l'instant `instant` : moyenne du stock sur les
    /// `fenetreNormaleJours` jours se terminant `exclusionRecenteJours` avant.
    static func normale(a instant: Date, contributions: [ContributionCharge], calendrier: Calendar) -> Double? {
        guard let fin = calendrier.date(byAdding: .day, value: -exclusionRecenteJours, to: instant),
              let debut = calendrier.date(byAdding: .day, value: -fenetreNormaleJours, to: fin)
        else { return nil }
        return moyenneChargeActive(de: debut, a: fin, contributions: contributions)
    }

    // MARK: Marche

    /// Préfiltrage : heures contenant assez de pas pour porter au moins la
    /// moitié d'un bout minimal (un bout de 10 min à 100 pas/min laisse
    /// ≥ 500 pas dans au moins une des heures qu'il touche), élargies d'une
    /// heure de part et d'autre puis fusionnées. Seules ces plages sont
    /// relues à la minute — évite ~100 000 buckets sur l'historique complet.
    static func plagesCandidates(pasParHeure: [PasHeure]) -> [DateInterval] {
        let seuil = cadenceMarcheMin * Double(dureeMarcheMinMinutes) / 2
        let plages = pasParHeure
            .filter { $0.pas >= seuil }
            .map { DateInterval(start: $0.debut.addingTimeInterval(-3600), duration: 3 * 3600) }
            .sorted { $0.start < $1.start }
        var fusion: [DateInterval] = []
        for plage in plages {
            if let derniere = fusion.last, plage.start <= derniere.end {
                fusion[fusion.count - 1] = DateInterval(start: derniere.start, end: max(derniere.end, plage.end))
            } else {
                fusion.append(plage)
            }
        }
        return fusion
    }

    /// Bouts de marche soutenue : minutes **consécutives** à au moins
    /// `cadenceMarcheMin` pas, sur au moins `dureeMarcheMinMinutes`. Une
    /// minute absente de la série compte comme une minute à 0 pas.
    static func boutsMarche(pasParMinute: [PasMinute]) -> [BoutMarche] {
        let minutes = pasParMinute.sorted { $0.debut < $1.debut }
        var bouts: [BoutMarche] = []
        var courant: [PasMinute] = []

        func clore() {
            if courant.count >= dureeMarcheMinMinutes, let premier = courant.first, let dernier = courant.last {
                bouts.append(BoutMarche(
                    debut: premier.debut,
                    fin: dernier.debut.addingTimeInterval(60),
                    pas: courant.reduce(0) { $0 + $1.pas }
                ))
            }
            courant.removeAll()
        }

        for minute in minutes {
            guard minute.pas >= cadenceMarcheMin else { clore(); continue }
            if let dernier = courant.last, minute.debut.timeIntervalSince(dernier.debut) > 60.5 {
                clore()
            }
            courant.append(minute)
        }
        clore()
        return bouts
    }

    /// Dédoublonnage : un bout qui chevauche une séance enregistrée (hub ou
    /// workout Apple Santé) est entièrement écarté — la séance le compte déjà.
    static func exclureChevauchements(_ bouts: [BoutMarche], seances: [DateInterval]) -> [BoutMarche] {
        bouts.filter { bout in
            !seances.contains { $0.start < bout.fin && bout.debut < $0.end }
        }
    }

    // MARK: Hystérésis

    /// Niveau visé par un jour d'indice `indice`, depuis le niveau `courant`.
    /// Entrée à ±`seuilEcartTendance`, maintien tant qu'on ne repasse pas le
    /// seuil de sortie ±`seuilSortieNiveau`.
    static func niveauVise(indice: Double, depuis courant: NiveauChargeActive) -> NiveauChargeActive {
        let entree = CalculChargeContinue.seuilEcartTendance
        let sortie = CalculChargeContinue.seuilSortieNiveau
        if indice >= 1 + entree { return .haute }
        if indice <= 1 - entree { return .basse }
        if courant == .haute && indice > 1 + sortie { return .haute }
        if courant == .basse && indice < 1 - sortie { return .basse }
        return .normale
    }

    /// Rejoue la bande d'hystérésis sur une série d'indices journaliers
    /// (plus ancien en premier). Un changement de niveau — entrée **ou**
    /// sortie — n'est acté qu'après `joursMinimumTendance` jours consécutifs
    /// visant un autre niveau que le courant ; il prend alors le niveau visé
    /// le dernier jour. Un jour sans indice (`nil`) remet le compteur à zéro.
    ///
    /// - Returns: niveau final et nombre de jours depuis la dernière bascule
    ///   (`nil` si aucune bascule sur la série).
    static func niveau(
        indicesJournaliers: [Double?],
        depart: NiveauChargeActive = .normale
    ) -> (niveau: NiveauChargeActive, depuisJours: Int?) {
        var niveau = depart
        var joursEcart = 0
        var indexBascule: Int?
        for (index, indice) in indicesJournaliers.enumerated() {
            guard let indice else { joursEcart = 0; continue }
            let vise = niveauVise(indice: indice, depuis: niveau)
            if vise == niveau {
                joursEcart = 0
                continue
            }
            joursEcart += 1
            if joursEcart >= CalculChargeContinue.joursMinimumTendance {
                niveau = vise
                joursEcart = 0
                // La bascule date du premier jour de la série d'écart.
                indexBascule = index - CalculChargeContinue.joursMinimumTendance + 1
            }
        }
        let depuis = indexBascule.map { indicesJournaliers.count - $0 }
        return (niveau, depuis)
    }

    // MARK: Assemblage

    static func contributions(seances: [SeancePourCharge], bouts: [BoutMarche]) -> [ContributionCharge] {
        seances.map { ContributionCharge(instant: $0.fin, charge: charge($0), source: .seance) }
            + bouts.map { ContributionCharge(instant: $0.fin, charge: charge($0), source: .marche) }
    }

    /// - Parameters:
    ///   - seances: séances du hub sur `profondeurJours`.
    ///   - bouts: bouts de marche **déjà dédoublonnés**, `nil` si les pas
    ///     n'ont pas pu être lus (charge partielle).
    ///   - debutHistorique: date de la plus ancienne donnée d'activité
    ///     disponible (premier pas enregistré, sinon première séance) — `nil`
    ///     si aucune. En deçà de la fenêtre de référence : pas de normale.
    static func analyser(
        seances: [SeancePourCharge],
        bouts: [BoutMarche]?,
        debutHistorique: Date?,
        maintenant: Date = Date(),
        calendrier: Calendar = .current
    ) -> SyntheseChargeActive {
        let marcheIncluse = bouts != nil
        let apports = contributions(seances: seances, bouts: bouts ?? [])

        guard let debutHistorique,
              let debutRequis = calendrier.date(
                  byAdding: .day, value: -(fenetreNormaleJours + exclusionRecenteJours), to: maintenant),
              debutHistorique <= debutRequis,
              let normaleActuelle = normale(a: maintenant, contributions: apports, calendrier: calendrier)
        else {
            return SyntheseChargeActive(etat: .pasAssezDeRecul, marcheIncluse: marcheIncluse)
        }
        guard normaleActuelle > 0 else {
            return SyntheseChargeActive(etat: .aucuneActiviteDeReference, marcheIncluse: marcheIncluse)
        }

        let indice = chargeActive(a: maintenant, contributions: apports) / normaleActuelle
        let serie = indicesJournaliers(
            contributions: apports, debutHistorique: debutHistorique,
            maintenant: maintenant, calendrier: calendrier
        )
        let (niveauFinal, depuis) = Self.niveau(indicesJournaliers: serie)
        return SyntheseChargeActive(
            etat: .disponible(indice: indice, niveau: niveauFinal, depuisJours: depuis),
            marcheIncluse: marcheIncluse
        )
    }

    /// Indice de chaque jour calendaire des `joursSerieNiveau` derniers jours
    /// (aujourd'hui inclus, jusqu'à `maintenant`) : **moyenne du stock sur la
    /// journée** / normale de ce jour. La moyenne journalière, plutôt que la
    /// valeur à un instant fixe, lisse le pic qui suit chaque séance — le
    /// niveau décrit un régime, pas l'heure de la dernière sortie.
    static func indicesJournaliers(
        contributions: [ContributionCharge],
        debutHistorique: Date,
        maintenant: Date,
        calendrier: Calendar
    ) -> [Double?] {
        let aujourdhui = calendrier.startOfDay(for: maintenant)
        return (0..<joursSerieNiveau).map { offset -> Double? in
            guard let jour = calendrier.date(byAdding: .day, value: -(joursSerieNiveau - 1 - offset), to: aujourdhui),
                  let lendemain = calendrier.date(byAdding: .day, value: 1, to: jour)
            else { return nil }
            let fin = min(lendemain, maintenant)
            guard let debutRequis = calendrier.date(
                      byAdding: .day, value: -(fenetreNormaleJours + exclusionRecenteJours), to: fin),
                  debutHistorique <= debutRequis,
                  let normaleJour = normale(a: fin, contributions: contributions, calendrier: calendrier),
                  normaleJour > 0
            else { return nil }
            return moyenneChargeActive(de: jour, a: fin, contributions: contributions) / normaleJour
        }
    }
}
