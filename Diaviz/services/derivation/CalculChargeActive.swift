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

/// Nombre de pas d'un bloc de `CalculChargeActive.dureeBlocMinutes` minutes
/// — sert uniquement au préfiltrage des plages à relire à la minute
/// (`plagesCandidates`).
nonisolated struct PasBloc: Sendable, Equatable {
    let debut: Date
    let pas: Double
}

/// Bout de marche soutenue détecté dans les pas (hors séance enregistrée).
nonisolated struct BoutMarche: Sendable, Equatable, Codable {
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

/// Niveau de charge active — **seul** vocabulaire « charge basse / normale /
/// haute » de l'app. Accueil exclu : il affiche des faits (minutes), pas un
/// niveau.
nonisolated enum NiveauChargeActive: String, Sendable, Equatable, CaseIterable {
    case basse, normale, haute

    var libelle: String {
        switch self {
        case .basse:   "Charge active basse"
        case .normale: "Charge active dans la référence"
        case .haute:   "Charge active haute"
        }
    }

    /// « basse » / « dans la référence » / « haute » — pour les pastilles.
    var libelleCourt: String {
        switch self {
        case .basse:   "basse"
        case .normale: "dans la référence"
        case .haute:   "haute"
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
    /// `indice` = moyenne du stock sur la journée (jusqu'à l'instant lu) /
    /// normale personnelle — la même lecture que celle qui fixe le niveau.
    /// La valeur à l'instant, qui bondit juste après chaque séance, n'est
    /// plus affichée : « normale » à côté de « +53 % » se contredisait.
    /// `depuisJours` = jours depuis la dernière bascule de niveau, `nil` si
    /// aucune bascule observée.
    case disponible(indice: Double, niveau: NiveauChargeActive, depuisJours: Int?)
}

nonisolated struct SyntheseChargeActive: Sendable, Equatable {
    let etat: EtatChargeActive
    /// `false` quand les pas n'ont pas pu être lus (autorisation Santé
    /// refusée ou aucun pas enregistré) : charge sur les séances seules,
    /// à signaler comme partielle.
    let marcheIncluse: Bool

    var niveau: NiveauChargeActive? {
        if case let .disponible(_, niveau, _) = etat { return niveau }
        return nil
    }
}

/// Un jour calendaire : faits bruts (minutes) et lecture relative (indice,
/// niveau). Les faits sont toujours peuplés ; l'indice et le niveau peuvent
/// manquer faute de recul.
nonisolated struct JourChargeActive: Sendable, Equatable, Identifiable {
    let jour: Date
    let nombreSeances: Int
    let minutesSeances: Double
    let minutesMarche: Double
    /// Moyenne du stock sur la journée / normale de ce jour.
    let indice: Double?
    /// Niveau après bande d'hystérésis — `nil` tant qu'aucun indice n'a
    /// jamais été calculable sur la série.
    let niveau: NiveauChargeActive?
    let depuisJours: Int?

    var id: Date { jour }
}

/// Référence traduite en faits hebdomadaires moyens (voir
/// `ContexteChargeActive.referenceEnFaits`).
nonisolated struct ReferenceEnFaits: Sendable, Equatable {
    let seancesParSemaine: Double
    let minutesSeancesParSemaine: Double
    let minutesMarcheParSemaine: Double
}

/// Contexte de charge active calculé **une fois** et partagé par tous les
/// écrans (analyses, badges, B2/B3, accueil). Le niveau d'un jour donné est
/// rejoué une seule fois sur toute la série : deux écrans qui parlent du
/// même jour lisent forcément le même niveau.
nonisolated struct ContexteChargeActive: Sendable {
    let contributions: [ContributionCharge]
    let debutHistorique: Date?
    let marcheIncluse: Bool
    /// Chronologique, `CalculChargeActive.horizonJours` jours jusqu'à aujourd'hui.
    let jours: [JourChargeActive]
    let calendrier: Calendar

    static let vide = ContexteChargeActive(
        contributions: [], debutHistorique: nil, marcheIncluse: false, jours: [], calendrier: .current
    )

    func jour(contenant date: Date) -> JourChargeActive? {
        let debut = calendrier.startOfDay(for: date)
        return jours.first { $0.jour == debut }
    }

    func niveau(le date: Date) -> NiveauChargeActive? {
        jour(contenant: date)?.niveau
    }

    /// Niveau par début de jour — entrée des calculateurs purs B2/B3.
    var niveauxParJour: [Date: NiveauChargeActive] {
        Dictionary(jours.compactMap { j in j.niveau.map { (j.jour, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Lecture à un instant : indice et niveau du jour qui le contient (jour
    /// passé : moyenne de toute la journée ; aujourd'hui : jusqu'au dernier
    /// calcul). Hors horizon, le jour est rejoué à la demande.
    func synthese(a instant: Date) -> SyntheseChargeActive {
        let normale = CalculChargeActive.normale(a: instant, contributions: contributions, calendrier: calendrier)
        guard CalculChargeActive.reculSuffisant(a: instant, debutHistorique: debutHistorique, calendrier: calendrier),
              let normale
        else { return SyntheseChargeActive(etat: .pasAssezDeRecul, marcheIncluse: marcheIncluse) }
        guard normale > 0 else {
            return SyntheseChargeActive(etat: .aucuneActiviteDeReference, marcheIncluse: marcheIncluse)
        }
        let jourConnu = jour(contenant: instant).flatMap { $0.niveau == nil ? nil : $0 }
        let jourLu = jourConnu ?? CalculChargeActive.jours(
            contributions: contributions, seances: [], bouts: [], debutHistorique: debutHistorique,
            jusqua: instant, horizonJours: 1, calendrier: calendrier
        ).last
        guard let niveau = jourLu?.niveau else {
            return SyntheseChargeActive(etat: .pasAssezDeRecul, marcheIncluse: marcheIncluse)
        }
        let indice = jourLu?.indice
            ?? CalculChargeActive.chargeActive(a: instant, contributions: contributions) / normale
        return SyntheseChargeActive(
            etat: .disponible(indice: indice, niveau: niveau, depuisJours: jourLu?.depuisJours),
            marcheIncluse: marcheIncluse
        )
    }

    /// La référence en **faits** : séances et marche soutenue par semaine,
    /// en moyenne sur la fenêtre de la normale lue en `instant` (4 semaines,
    /// hors semaine juste avant). Jamais le stock brut, sans unité parlante.
    /// `nil` sans assez de recul ou si la fenêtre sort de l'horizon.
    func referenceEnFaits(a instant: Date) -> ReferenceEnFaits? {
        guard CalculChargeActive.reculSuffisant(a: instant, debutHistorique: debutHistorique, calendrier: calendrier),
              let finInstant = calendrier.date(byAdding: .day, value: -CalculChargeActive.exclusionRecenteJours, to: instant),
              // Jours entiers : exactement `fenetreNormaleJours` jours comptés.
              case let fin = calendrier.startOfDay(for: finInstant),
              let debut = calendrier.date(byAdding: .day, value: -CalculChargeActive.fenetreNormaleJours, to: fin),
              let premier = jours.first, premier.jour <= debut
        else { return nil }
        let fenetre = jours.filter { $0.jour >= debut && $0.jour < fin }
        let semaines = Double(CalculChargeActive.fenetreNormaleJours) / 7
        return ReferenceEnFaits(
            seancesParSemaine: Double(fenetre.reduce(0) { $0 + $1.nombreSeances }) / semaines,
            minutesSeancesParSemaine: fenetre.reduce(0) { $0 + $1.minutesSeances } / semaines,
            minutesMarcheParSemaine: fenetre.reduce(0) { $0 + $1.minutesMarche } / semaines
        )
    }

    /// Moyenne du stock sur `[debut, fin]` rapportée à la normale en `fin`
    /// — lecture d'une semaine entière. `nil` sans recul ou sans normale.
    func indiceMoyen(de debut: Date, a fin: Date) -> Double? {
        guard CalculChargeActive.reculSuffisant(a: fin, debutHistorique: debutHistorique, calendrier: calendrier),
              let normale = CalculChargeActive.normale(a: fin, contributions: contributions, calendrier: calendrier),
              normale > 0
        else { return nil }
        return CalculChargeActive.moyenneChargeActive(de: debut, a: fin, contributions: contributions) / normale
    }
}

// MARK: - Calculateur

/// **Charge active** — ce qui reste de sensibilité gagnée par les séances
/// passées. Chaque séance (et chaque bout de marche soutenue) alimente un
/// stock qui décroît de façon exponentielle (demi-vie 24 h). Même forme que
/// `IOBCalculateur`, sans pic différé.
///
///     charge_active(T) = Σ charge_i · exp(−ln2 / demi_vie · (T − t_i))
///
/// Remplace les deux anciens calculs (charge continue par jour sommée par
/// semaine, et paliers de séances sur 7 jours) : un seul calcul de charge
/// dans l'app. Dérivation pure, jamais persistée. Doc canonique :
/// `docs/architecture/Diaviz — Charge active (sport).md`.
///
/// **Normale dans la même unité.** L'indice rapporte le stock à la
/// **moyenne temporelle du stock** sur la fenêtre de référence. En régime
/// établi, cette moyenne vaut `charge_journalière × τ` avec
/// `τ = demi_vie / ln2` ≈ 1,44 j : diviser par une somme hebdo / 7 ferait
/// sortir un indice de 1,44 pour une semaine parfaitement habituelle.
nonisolated enum CalculChargeActive {

    // MARK: Paramètres (registre : docs/architecture/Diaviz — Paramètres à calibrer.md)

    static let demiVieHeures = 24.0
    /// Fenêtre de la normale : 4 semaines, se terminant `exclusionRecenteJours`
    /// avant l'instant lu, pour que la normale ne suive pas la variation
    /// qu'elle doit révéler.
    static let fenetreNormaleJours = 28
    static let exclusionRecenteJours = 7
    /// Jours rejoués **avant** l'horizon pour amorcer l'hystérésis — l'état de
    /// départ est supposé normal, il a le temps de converger.
    static let joursSerieNiveau = 28
    /// Marge avant la plus ancienne fenêtre : ~5 demi-vies, au-delà desquelles
    /// une séance ne pèse plus que ~3 % de sa charge.
    static let margeDecroissanceJours = 7
    /// Jours couverts par le contexte partagé : corrélation (10 semaines),
    /// corpus B2/B3 (60 nuits), avec marge.
    static let horizonJours = 90

    /// Facteurs d'intensité saisie — faible 1, modérée 2, intense 3
    /// (`session-RPE` de Foster : durée × intensité ressentie).
    static func facteur(_ intensite: IntensiteSport) -> Double {
        switch intensite {
        case .faible:   1.0
        case .moderee:  2.0
        case .intense:  3.0
        }
    }

    /// Hystérésis : entrée en haut/bas à ±40 %, sortie en repassant ±25 %,
    /// après `joursMinimumBascule` jours consécutifs.
    static let seuilEntreeNiveau = 0.4
    static let seuilSortieNiveau = 0.25
    static let joursMinimumBascule = 3

    static let cadenceMarcheMin = 100.0
    static let dureeMarcheMinMinutes = 10
    static let coefficientMarche = 0.75
    /// Taille des blocs du préfiltrage — égale à la durée minimale d'un bout.
    static let dureeBlocMinutes = 10
    /// Deux plages candidates séparées de moins que ça sont relues en une
    /// seule requête minute : le coût d'une requête HealthKit tient surtout
    /// à son existence, pas au nombre de minutes lues.
    static let ecartFusionPlagesMinutes = 180

    /// FC max théorique — même valeur que `intensiteDepuisFC`.
    static let fcMaxTheorique = 190.0

    /// Profondeur d'historique totale à charger pour construire le contexte.
    static var profondeurJours: Int {
        horizonJours + joursSerieNiveau + fenetreNormaleJours + exclusionRecenteJours + margeDecroissanceJours
    }

    static var lambdaParSeconde: Double { log(2) / (demiVieHeures * 3600) }

    // MARK: Pondération

    /// Coefficient par famille d'activité — 1 partout tant qu'aucune donnée
    /// ne justifie de différencier (doc § 5). Le type est capté pour plus tard.
    static func coefficientType(_ typeActiviteHK: UInt?) -> Double { 1.0 }

    /// Facteur d'intensité : FC moyenne si disponible, interpolée en continu
    /// sur les mêmes zones que `intensiteDepuisFC` (50 % FCmax → 1, 70 % → 2,
    /// 90 % → 3, borné à [1, 3]) ; sinon l'intensité saisie.
    static func facteurIntensite(_ seance: SeancePourCharge) -> Double {
        guard let fc = seance.fcMoyenne, fc > 0 else { return facteur(seance.intensite) }
        let pourcentage = fc / fcMaxTheorique
        return min(3, max(1, 1 + (pourcentage - 0.5) / 0.2))
    }

    static func charge(_ seance: SeancePourCharge) -> Double {
        coefficientType(seance.typeActiviteHK) * facteurIntensite(seance) * Double(seance.dureeMin)
    }

    /// Un bout de marche pèse comme une séance faible, réduite par
    /// `coefficientMarche`.
    static func charge(_ bout: BoutMarche) -> Double {
        coefficientMarche * facteur(.faible) * bout.dureeMin
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

    /// Début de l'historique exploitable : la date **la plus tardive** des
    /// sources présentes. Les pas remontent souvent à des années, mais les
    /// séances ne sont saisies que depuis la première du hub : avant elle,
    /// une normale ne verrait que la marche et serait sous-estimée — l'indice
    /// exploserait (constaté sur les premières semaines d'historique).
    static func debutHistorique(premierPas: Date?, premiereSeance: Date?) -> Date? {
        [premierPas, premiereSeance].compactMap { $0 }.max()
    }

    /// L'historique couvre-t-il toute la fenêtre de la normale lue en `instant` ?
    static func reculSuffisant(a instant: Date, debutHistorique: Date?, calendrier: Calendar) -> Bool {
        guard let debutHistorique,
              let requis = calendrier.date(
                  byAdding: .day, value: -(fenetreNormaleJours + exclusionRecenteJours), to: instant)
        else { return false }
        return debutHistorique <= requis
    }

    // MARK: Marche

    /// Préfiltrage : paires de blocs de 10 min consécutifs totalisant au
    /// moins un bout minimal (10 min × 100 pas = 1 000 pas). Condition
    /// **nécessaire** : un bout de 10 min tient dans deux blocs voisins, et
    /// chaque tranche de 10 min d'un bout plus long aussi — aucun bout ne
    /// peut échapper au filtre. Seules ces plages sont relues à la minute.
    ///
    /// Remplace un filtre par heures ≥ 500 pas, trop lâche : sur l'iPhone de
    /// l'utilisateur, 220 plages et 6 s de lecture pour 0 bout (2026-09-26).
    static func plagesCandidates(pasParBloc: [PasBloc]) -> [DateInterval] {
        let seuil = cadenceMarcheMin * Double(dureeMarcheMinMinutes)
        let pas = TimeInterval(dureeBlocMinutes * 60)
        let parDebut = Dictionary(pasParBloc.map { ($0.debut, $0.pas) }, uniquingKeysWith: +)
        let plages = pasParBloc
            .filter { $0.pas + (parDebut[$0.debut.addingTimeInterval(pas)] ?? 0) >= seuil }
            .map { DateInterval(start: $0.debut, duration: 2 * pas) }
            .sorted { $0.start < $1.start }
        var fusion: [DateInterval] = []
        for plage in plages {
            if let derniere = fusion.last,
               plage.start.timeIntervalSince(derniere.end) <= Double(ecartFusionPlagesMinutes * 60) {
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

    /// Bouts en cache (jours clos, avant `coupure`) + bouts relus depuis
    /// `coupure`. Un bout relu qui recoupe le dernier bout en cache (bout à
    /// cheval sur la coupure, relu tronqué) est écarté.
    static func fusionnerBouts(cache: [BoutMarche], nouveaux: [BoutMarche], coupure: Date) -> [BoutMarche] {
        let anciens = cache.filter { $0.debut < coupure }
        let finAnciens = anciens.map(\.fin).max() ?? .distantPast
        return anciens + nouveaux.filter { $0.debut >= coupure && $0.debut >= finAnciens }
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
    static func niveauVise(indice: Double, depuis courant: NiveauChargeActive) -> NiveauChargeActive {
        if indice >= 1 + seuilEntreeNiveau { return .haute }
        if indice <= 1 - seuilEntreeNiveau { return .basse }
        if courant == .haute && indice > 1 + seuilSortieNiveau { return .haute }
        if courant == .basse && indice < 1 - seuilSortieNiveau { return .basse }
        return .normale
    }

    /// Rejoue la bande d'hystérésis jour par jour (plus ancien en premier).
    /// Un changement de niveau — entrée **ou** sortie — n'est acté qu'après
    /// `joursMinimumBascule` jours consécutifs visant un autre niveau ; il
    /// prend le niveau visé le dernier jour et date du premier jour de la
    /// série d'écart. Avant le premier indice calculable, niveau `nil` ;
    /// ensuite, départ en normal. Un jour sans indice remet le compteur à
    /// zéro sans changer le niveau.
    static func niveauxSuccessifs(
        indicesJournaliers: [Double?]
    ) -> [(niveau: NiveauChargeActive?, depuisJours: Int?)] {
        var niveau: NiveauChargeActive?
        var joursEcart = 0
        var indexBascule: Int?
        var resultat: [(niveau: NiveauChargeActive?, depuisJours: Int?)] = []
        for (index, indice) in indicesJournaliers.enumerated() {
            if let indice {
                let courant = niveau ?? .normale
                niveau = courant
                let vise = niveauVise(indice: indice, depuis: courant)
                if vise == courant {
                    joursEcart = 0
                } else {
                    joursEcart += 1
                    if joursEcart >= joursMinimumBascule {
                        niveau = vise
                        joursEcart = 0
                        indexBascule = index - joursMinimumBascule + 1
                    }
                }
            } else {
                joursEcart = 0
            }
            resultat.append((niveau, indexBascule.map { index - $0 + 1 }))
        }
        return resultat
    }

    /// Niveau final d'une série — `.normale` si aucun indice.
    static func niveau(indicesJournaliers: [Double?]) -> (niveau: NiveauChargeActive, depuisJours: Int?) {
        let dernier = niveauxSuccessifs(indicesJournaliers: indicesJournaliers).last
        return (dernier?.niveau ?? .normale, dernier?.depuisJours)
    }

    // MARK: Assemblage

    static func contributions(seances: [SeancePourCharge], bouts: [BoutMarche]) -> [ContributionCharge] {
        seances.map { ContributionCharge(instant: $0.fin, charge: charge($0), source: .seance) }
            + bouts.map { ContributionCharge(instant: $0.fin, charge: charge($0), source: .marche) }
    }

    /// Contexte partagé sur `horizonJours` jours jusqu'à `maintenant`.
    ///
    /// - Parameters:
    ///   - seances: séances du hub sur `profondeurJours`.
    ///   - bouts: bouts de marche **déjà dédoublonnés**, `nil` si les pas
    ///     n'ont pas pu être lus (charge partielle).
    ///   - debutHistorique: plus ancienne donnée d'activité disponible
    ///     (premier pas enregistré, sinon première séance).
    static func contexte(
        seances: [SeancePourCharge],
        bouts: [BoutMarche]?,
        debutHistorique: Date?,
        maintenant: Date = Date(),
        horizonJours: Int = horizonJours,
        calendrier: Calendar = .current
    ) -> ContexteChargeActive {
        let apports = contributions(seances: seances, bouts: bouts ?? [])
        return ContexteChargeActive(
            contributions: apports,
            debutHistorique: debutHistorique,
            marcheIncluse: bouts != nil,
            jours: jours(
                contributions: apports, seances: seances, bouts: bouts ?? [],
                debutHistorique: debutHistorique, jusqua: maintenant,
                horizonJours: horizonJours, calendrier: calendrier
            ),
            calendrier: calendrier
        )
    }

    /// Lecture à `maintenant` (raccourci de `contexte(...).synthese(a:)`).
    static func analyser(
        seances: [SeancePourCharge],
        bouts: [BoutMarche]?,
        debutHistorique: Date?,
        maintenant: Date = Date(),
        calendrier: Calendar = .current
    ) -> SyntheseChargeActive {
        contexte(
            seances: seances, bouts: bouts, debutHistorique: debutHistorique,
            maintenant: maintenant, horizonJours: 1, calendrier: calendrier
        ).synthese(a: maintenant)
    }

    /// Série des `horizonJours` derniers jours (aujourd'hui inclus, jusqu'à
    /// `jusqua`), hystérésis amorcée `joursSerieNiveau` jours plus tôt.
    ///
    /// Indice d'un jour = **moyenne du stock sur la journée** / normale de ce
    /// jour : la moyenne journalière, plutôt que la valeur à un instant fixe,
    /// lisse le pic qui suit chaque séance — le niveau décrit un régime, pas
    /// l'heure de la dernière sortie.
    static func jours(
        contributions: [ContributionCharge],
        seances: [SeancePourCharge],
        bouts: [BoutMarche],
        debutHistorique: Date?,
        jusqua: Date,
        horizonJours: Int,
        calendrier: Calendar
    ) -> [JourChargeActive] {
        let aujourdhui = calendrier.startOfDay(for: jusqua)
        let total = horizonJours + joursSerieNiveau
        let debuts: [Date] = (0..<total).compactMap {
            calendrier.date(byAdding: .day, value: -(total - 1 - $0), to: aujourdhui)
        }
        let indices: [Double?] = debuts.map { jour in
            guard let lendemain = calendrier.date(byAdding: .day, value: 1, to: jour) else { return nil }
            let fin = min(lendemain, jusqua)
            guard reculSuffisant(a: fin, debutHistorique: debutHistorique, calendrier: calendrier),
                  let normaleJour = normale(a: fin, contributions: contributions, calendrier: calendrier),
                  normaleJour > 0
            else { return nil }
            return moyenneChargeActive(de: jour, a: fin, contributions: contributions) / normaleJour
        }
        let niveaux = niveauxSuccessifs(indicesJournaliers: indices)

        var seancesParJour: [Date: (nombre: Int, minutes: Double)] = [:]
        for s in seances {
            let jour = calendrier.startOfDay(for: s.debut)
            let cumul = seancesParJour[jour] ?? (0, 0)
            seancesParJour[jour] = (cumul.nombre + 1, cumul.minutes + Double(s.dureeMin))
        }
        var marcheParJour: [Date: Double] = [:]
        for b in bouts {
            marcheParJour[calendrier.startOfDay(for: b.debut), default: 0] += b.dureeMin
        }

        return debuts.indices.suffix(horizonJours).map { i in
            let jour = debuts[i]
            return JourChargeActive(
                jour: jour,
                nombreSeances: seancesParJour[jour]?.nombre ?? 0,
                minutesSeances: seancesParJour[jour]?.minutes ?? 0,
                minutesMarche: marcheParJour[jour] ?? 0,
                indice: indices[i],
                niveau: niveaux[i].niveau,
                depuisJours: niveaux[i].depuisJours
            )
        }
    }
}
