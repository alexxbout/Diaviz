//
//  CalculRepasARevoir.swift
//  diaviz
//

import Foundation

/// Regroupe les repas récents par composition et remonte ceux dont la
/// **dernière** occurrence a un verdict mauvais — alimente la section accueil
/// « Repas à revoir ».
///
/// Distinct du mining `CalculRatioObserve` (qui lit `verdictPersiste` sur
/// tout l'historique) : ici il faut afficher une vraie courbe CGM par
/// occurrence, or `ReponseGlycemique.pointsCgm` n'est jamais persistée
/// (`etatAnalyse` reste `@Transient`) — donc le regroupement ne porte que sur
/// les repas **récents** encore en mémoire (même fenêtre qu'`AssembleurReponseRepas`).
///
/// Matching sans LLM (garde-fou validé) : signature = aliments dont les
/// glucides dépassent un seuil (ignore garnitures négligeables), noms
/// normalisés comparés par égalité stricte + glucides totaux à ±15g de
/// tolérance. Accepte de rater un doublon cherché sous un nom OFF différent
/// plutôt que de risquer un faux regroupement.
nonisolated enum CalculRepasARevoir {

    /// Fenêtre de repas exploitables — mêmes bornes qu'`AssembleurReponseRepas`
    /// côté `RepasService` (backfill Dexcom borné, inutile de regarder plus loin
    /// pour une courbe CGM affichable).
    static let fenetreJours = 45
    /// Glucides (g) au-delà desquels un aliment pilote la signature du repas.
    static let seuilGlucidesDominant = 10
    /// Tolérance (g) sur les glucides totaux vs le dernier repas du groupe.
    static let toleranceGlucides = 15
    /// Occurrences minimales par défaut pour qu'un groupe soit « récurrent ».
    /// Seul seuil de fiabilité pour cette carte — contrairement au mining
    /// (`CalculRatioObserve`), ce n'est pas une inférence statistique globale
    /// mais la remontée d'un fait direct (ce repas précis, répété, a mal
    /// tourné la dernière fois) : pas besoin d'attendre 30 repas au total
    /// pour que ce soit vrai et utile, même chose que « Repas avec contexte »
    /// qui n'a délibérément aucun seuil global.
    ///
    /// Réglable par l'utilisateur (`ProfilUtilisateur.preferencesAvancees`) —
    /// cette constante n'est que le défaut si rien n'est configuré.
    static let occurrencesMinimalesParDefaut = 2
    static let maxCartes = 10

    // MARK: - Point d'entrée

    static func analyser(
        repas: [Repas],
        injections: [Injection] = [],
        activites: [ActiviteSportive] = [],
        horairesRepas: HorairesRepas,
        seuils: SeuilsGlycemiques = SeuilsGlycemiques(),
        occurrencesMinimales: Int = occurrencesMinimalesParDefaut,
        idsMasques: Set<UUID> = [],
        maintenant: Date = Date()
    ) -> [RepasARevoir] {
        let borne = maintenant.addingTimeInterval(-Double(fenetreJours) * 86_400)
        let recents = repas.filter { $0.heure >= borne && !$0.exclureDesAnalyses }

        var groupes: [Set<String>: [Repas]] = [:]
        for r in recents {
            guard case .disponible = r.etatAnalyse else { continue }
            groupes[signature(r), default: []].append(r)
        }

        let cartes = groupes.values.compactMap {
            construireCarte(
                $0,
                horairesRepas: horairesRepas,
                seuils: seuils,
                injections: injections,
                activites: activites,
                tousRepas: recents,
                occurrencesMinimales: occurrencesMinimales
            )
        }
        // Masquage par occurrence précise (`idRepasSource` = id du dernier
        // repas ayant motivé la carte), pas par groupe/signature : si ce
        // même repas se reproduit avec un nouveau mauvais résultat, le
        // "dernier" devient un nouveau `Repas` (nouvel id, absent du set
        // masqué) et la carte réapparaît automatiquement — masquer une
        // carte ne fait taire QUE l'alerte actuelle, jamais le plat pour
        // toujours.
        let visibles = cartes.filter { !idsMasques.contains($0.idRepasSource) }

        return visibles
            .sorted(by: plusSevereEnPremier)
            .prefix(maxCartes)
            .map { $0 }
    }

    // MARK: - Signature de composition

    /// Ensemble des noms d'aliments dominants (glucides ≥ seuil), normalisés.
    /// Si aucun aliment ne dépasse le seuil, retombe sur le plus glucidique —
    /// garantit une signature non vide pour tout repas avec des glucides.
    static func signature(_ repas: Repas, seuilGlucides: Int = seuilGlucidesDominant) -> Set<String> {
        let dominants = repas.aliments.filter { $0.glucides >= seuilGlucides }
        let base = dominants.isEmpty
            ? [repas.aliments.max(by: { $0.glucides < $1.glucides })].compactMap { $0 }
            : dominants
        return Set(base.map { $0.nom.trimmingCharacters(in: .whitespaces).lowercased() })
    }

    // MARK: - Construction d'une carte

    private static func construireCarte(
        _ membres: [Repas],
        horairesRepas: HorairesRepas,
        seuils: SeuilsGlycemiques,
        injections: [Injection],
        activites: [ActiviteSportive],
        tousRepas: [Repas],
        occurrencesMinimales: Int
    ) -> RepasARevoir? {
        let tries = membres.sorted { $0.heure < $1.heure }
        guard let dernier = tries.last,
              case .disponible(let reponseDerniere) = dernier.etatAnalyse,
              reponseDerniere.verdict == .mauvais else { return nil }

        // Tolérance de portion : ne garde que les occurrences dont les
        // glucides totaux restent proches de la dernière (qui motive le
        // « à revoir »).
        let glucidesRef = dernier.totalGlucides
        let occurrences = tries.filter { abs($0.totalGlucides - glucidesRef) <= toleranceGlucides }
        guard occurrences.count >= occurrencesMinimales else { return nil }

        guard let courbeDerniere = courbeAffichage(dernier) else { return nil }
        // Chaque occurrence passée conserve son verdict : la carte doit
        // pouvoir distinguer un plat qui rate systématiquement d'un plat qui
        // n'a raté qu'une fois. Sans ça, le nuage gris uniforme suggérait
        // « ça marche d'habitude », y compris quand c'était faux.
        let occurrencesPassees = occurrences.dropLast().compactMap { repas -> OccurrencePassee? in
            guard let points = courbeAffichage(repas) else { return nil }
            let horsCible: Bool
            if case .disponible(let reponse) = repas.etatAnalyse {
                horsCible = reponse.verdict == .mauvais
            } else {
                horsCible = false
            }
            return OccurrencePassee(points: points, horsCible: horsCible)
        }

        // Événement principal calculé sur la courbe **complète** (pas
        // tronquée à 180 min comme l'affichage) : une hypo tardive ne doit
        // pas être ratée à cause du domaine fixe du mini-chart.
        let postRepas = reponseDerniere.pointsCgm.filter { $0.secondesDepuisRepas >= 0 }
        let pointBas = postRepas.min { $0.valeur < $1.valeur }
        let estHypo = (pointBas?.valeur ?? .greatestFiniteMagnitude) < seuils.hypoglycemie
        let evenementMinutes = estHypo
            ? Int((pointBas?.secondesDepuisRepas ?? 0) / 60)
            : Int(reponseDerniere.tempsPic / 60)
        let evenementValeur = estHypo ? (pointBas?.valeur ?? 0) : reponseDerniere.valeurPic

        let glucidesValeurs = occurrences.map(\.totalGlucides)

        return RepasARevoir(
            aliments: dernier.aliments,
            nombreOccurrences: occurrences.count,
            occurrencesPassees: occurrencesPassees,
            pointsDerniereFois: courbeDerniere,
            evenementMinutes: evenementMinutes,
            evenementValeur: evenementValeur,
            estHypo: estHypo,
            glucidesMin: glucidesValeurs.min() ?? glucidesRef,
            glucidesMax: glucidesValeurs.max() ?? glucidesRef,
            libelleSection: SectionRepas(heure: dernier.heure, horaires: horairesRepas).titre,
            badgesAjustements: badgesAjustements(dernier),
            ratioApplique: dernier.ratioEffectifPersiste,
            evenements: evenements(
                pour: dernier, injections: injections, activites: activites, tousRepas: tousRepas
            ),
            heureDerniereOccurrence: dernier.heure,
            idRepasSource: dernier.id
        )
    }

    /// Fenêtre d'affichage des événements sur la courbe — même horizon que
    /// `courbeAffichage` (0…240 min = 4h, alignée sur `AssembleurReponseRepas.finFenetre`),
    /// pour qu'aucun marqueur ne tombe hors du graphe.
    ///
    /// Était fixée à 180 min : une hypo survenant après (fréquent, le pic
    /// post-prandial redescend souvent après 3h) avait son `PointMark` calculé
    /// sur la courbe complète mais jamais dessiné, le domaine du graphe
    /// s'arrêtant avant — l'événement le plus important de la carte restait
    /// invisible.
    static let fenetreEvenementsMinutes = 240

    /// Faits du hub survenus pendant la fenêtre post-repas, convertis en
    /// minutes depuis T0 : bolus du repas, corrections rapides, lente, autres
    /// repas, séances de sport. C'est ce qui permet de lire *pourquoi* la
    /// courbe a cette forme sans quitter l'accueil.
    ///
    /// Le sport est le seul fait à porter une durée (rendu en bande) et le
    /// seul retenu s'il **chevauche** la fenêtre plutôt que d'y commencer :
    /// une séance démarrée avant le repas continue d'agir après.
    /// Non-`private` : réutilisée par `CalculRepasContexte`.
    static func evenements(
        pour repas: Repas,
        injections: [Injection],
        activites: [ActiviteSportive],
        tousRepas: [Repas]
    ) -> [EvenementCourbe] {
        let t0 = repas.heure
        let fin = t0.addingTimeInterval(Double(fenetreEvenementsMinutes) * 60)
        func minutes(_ date: Date) -> Int { Int(date.timeIntervalSince(t0) / 60) }

        var resultat: [EvenementCourbe] = []

        // Bolus du repas lui-même — à T0, quelle que soit l'heure exacte de
        // l'injection liée (le décalage de saisie n'a pas de sens à afficher).
        // Libellé explicite (« Bolus repas 5,5 u ») plutôt que la seule dose :
        // sans le nom, rien ne distingue un bolus d'une correction ou d'une
        // lente dans la légende sous le graphe.
        //
        // `repas.totalInsuline` NE couvre QUE les glucides (dose globale ou
        // somme par aliment) — la correction d'hyper est stockée à part
        // (`repas.doseCorrection`) et injectée dans le **même** bolus
        // physique, donc jamais représentée par un `Injection` séparé
        // (exclu plus bas via `injection.repasAssocieId == repas.id`). Sans
        // cet événement dédié, la dose de correction de CE repas n'apparaissait
        // nulle part — impossible de savoir si "11u" incluait une correction.
        if repas.totalInsuline > 0 {
            resultat.append(EvenementCourbe(
                genre: .bolusRepas, minutes: 0,
                libelle: "Bolus repas \(repas.totalInsuline.doseInsulineFormatee)"
            ))
        }
        if let correction = repas.doseCorrection, correction > 0 {
            resultat.append(EvenementCourbe(
                genre: .correction, minutes: 0,
                libelle: "Correction \(correction.doseInsulineFormatee)"
            ))
        }

        for injection in injections where injection.heure > t0 && injection.heure <= fin {
            // Le bolus du repas est déjà posé à T0 ci-dessus.
            guard injection.repasAssocieId != repas.id else { continue }
            let genre: EvenementCourbe.Genre = injection.type == .lente ? .lente : .correction
            let nom = injection.type == .lente ? "Lente" : "Correction"
            resultat.append(EvenementCourbe(
                genre: genre, minutes: minutes(injection.heure),
                libelle: "\(nom) \(injection.dose.doseInsulineFormatee)"
            ))
        }

        for autre in tousRepas where autre.id != repas.id && autre.heure > t0 && autre.heure <= fin {
            // Distingue un resucrage (tous les aliments flaggés comme tels)
            // d'un vrai second repas — sans ça, « Repas 15 g » se lisait
            // comme le total du repas analysé (celui du titre de la carte),
            // alors que c'est un fait **distinct** survenu pendant la
            // fenêtre. Le mot juste évite l'ambiguïté.
            let estResucrage = !autre.aliments.isEmpty && autre.aliments.allSatisfy(\.resucrage)
            resultat.append(EvenementCourbe(
                genre: .repas, minutes: minutes(autre.heure),
                libelle: "\(estResucrage ? "Resucrage" : "Autre repas") \(autre.totalGlucides) g"
            ))
        }

        for activite in activites where activite.dateFin > t0 && activite.dateDebut <= fin {
            let debut = max(minutes(activite.dateDebut), 0)
            let finSeance = min(minutes(activite.dateFin), fenetreEvenementsMinutes)
            resultat.append(EvenementCourbe(
                genre: .sport,
                minutes: debut,
                dureeMinutes: max(finSeance - debut, 1),
                libelle: "\(activite.type.rawValue) \(activite.dureeMinutes) min"
            ))
        }

        return resultat.sorted { $0.minutes < $1.minutes }
    }

    /// Badges d'ajustement affichables (« Sport récent · Course à pied »),
    /// catégorisés (sport vs autre) pour la couleur. Toujours calculés,
    /// jamais utilisés pour filtrer — l'affichage reste honnête même sur un
    /// repas ajusté-sport. Non-`private` : réutilisée par `CalculRepasContexte`.
    static func badgesAjustements(_ repas: Repas) -> [BadgeAjustement] {
        repas.ajustements.map { ajustement in
            var libelle = ajustement.typeSportDetecte.map { "\(ajustement.raison.libelle) · \($0)" }
                ?? ajustement.raison.libelle
            // L'écart de dose fait partie du badge : « Sport récent » seul dit
            // pourquoi la dose a bougé, pas de combien — or c'est justement ce
            // qui manquait pour relire un repas ajusté.
            if ajustement.valeur != 0 {
                libelle += " \(ajustement.valeur.ecartDoseFormate)"
            }
            return BadgeAjustement(libelle: libelle, estSport: ajustement.raison == .sportRecent)
        }
    }

    /// Courbe pour affichage — tronquée à 0…240 min (4h) pour matcher le
    /// domaine du graphe (`CarteRepasARevoir`/`LigneRepasARevoir`) et la
    /// fenêtre réelle d'analyse post-repas (`AssembleurReponseRepas.finFenetre`).
    /// Non-`private` : réutilisée par `CalculRepasContexte`.
    static func courbeAffichage(_ repas: Repas) -> [PointCourbeRepas]? {
        guard case .disponible(let reponse) = repas.etatAnalyse else { return nil }
        return reponse.pointsCgm
            .filter { $0.secondesDepuisRepas >= 0 && $0.secondesDepuisRepas <= Double(fenetreEvenementsMinutes) * 60 }
            .map { PointCourbeRepas(minutes: Int($0.secondesDepuisRepas / 60), glycemie: $0.valeur) }
    }

    /// Hypos d'abord (plus dangereuses), puis par sévérité décroissante dans
    /// chaque groupe — une hypo profonde avant une hypo légère, un pic haut
    /// avant un pic modéré. Non-`private` : réutilisée par `CalculRepasContexte`.
    static func plusSevereEnPremier(_ a: RepasARevoir, _ b: RepasARevoir) -> Bool {
        if a.estHypo != b.estHypo { return a.estHypo }
        if a.estHypo { return a.evenementValeur < b.evenementValeur }
        return a.evenementValeur > b.evenementValeur
    }
}
