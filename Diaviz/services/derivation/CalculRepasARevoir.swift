//
//  CalculRepasARevoir.swift
//  diaviz
//

import Foundation

/// Regroupe les repas récents par composition et remonte ceux dont la
/// **dernière** occurrence a un verdict mauvais — alimente la section accueil
/// « Repas à revoir » (remplace `RepasAReevoirServiceMock`).
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
    /// Occurrences minimales pour qu'un groupe soit « récurrent ». Seul seuil
    /// de fiabilité pour cette carte — contrairement au mining
    /// (`CalculRatioObserve`), ce n'est pas une inférence statistique globale
    /// mais la remontée d'un fait direct (ce repas précis, répété, a mal
    /// tourné la dernière fois) : pas besoin d'attendre 30 repas au total
    /// pour que ce soit vrai et utile, même chose que « Repas avec contexte »
    /// qui n'a délibérément aucun seuil global.
    static let occurrencesMinimales = 2
    static let maxCartes = 10

    // MARK: - Point d'entrée

    static func analyser(
        repas: [Repas], horairesRepas: HorairesRepas, maintenant: Date = Date()
    ) -> [RepasARevoir] {
        let borne = maintenant.addingTimeInterval(-Double(fenetreJours) * 86_400)
        let recents = repas.filter { $0.heure >= borne && !$0.exclureDesAnalyses }

        var groupes: [Set<String>: [Repas]] = [:]
        for r in recents {
            guard case .disponible = r.etatAnalyse else { continue }
            groupes[signature(r), default: []].append(r)
        }

        let cartes = groupes.values.compactMap { construireCarte($0, horairesRepas: horairesRepas) }

        return cartes
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

    private static func construireCarte(_ membres: [Repas], horairesRepas: HorairesRepas) -> RepasARevoir? {
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
        let courbesPassees = occurrences.dropLast().compactMap(courbeAffichage)

        // Événement principal calculé sur la courbe **complète** (pas
        // tronquée à 180 min comme l'affichage) : une hypo tardive ne doit
        // pas être ratée à cause du domaine fixe du mini-chart.
        let postRepas = reponseDerniere.pointsCgm.filter { $0.secondesDepuisRepas >= 0 }
        let pointBas = postRepas.min { $0.valeur < $1.valeur }
        let estHypo = (pointBas?.valeur ?? .greatestFiniteMagnitude) < 70
        let evenementMinutes = estHypo
            ? Int((pointBas?.secondesDepuisRepas ?? 0) / 60)
            : Int(reponseDerniere.tempsPic / 60)
        let evenementValeur = estHypo ? (pointBas?.valeur ?? 0) : reponseDerniere.valeurPic

        let glucidesValeurs = occurrences.map(\.totalGlucides)

        return RepasARevoir(
            aliments: dernier.aliments,
            nombreOccurrences: occurrences.count,
            pointsOccurrencesPassees: Array(courbesPassees),
            pointsDerniereFois: courbeDerniere,
            evenementMinutes: evenementMinutes,
            evenementValeur: evenementValeur,
            estHypo: estHypo,
            glucidesMin: glucidesValeurs.min() ?? glucidesRef,
            glucidesMax: glucidesValeurs.max() ?? glucidesRef,
            libelleSection: libelleSectionAvecRatio(dernier, horairesRepas: horairesRepas),
            badgesAjustements: badgesAjustements(dernier)
        )
    }

    /// Badge « Déjeuner · 1u/12g » — moment de la journée + ratio effectif du
    /// repas (grammes de glucides par unité, déjà persisté). Le ratio prime
    /// sur les glucides bruts (déjà affichés en fourchette plus bas sur la
    /// carte) : c'est lui qui explique le verdict, pas la quantité seule. Pas
    /// de ratio affiché si `ratioEffectifPersiste` est inconnu (repli gracieux).
    /// Non-`private` : réutilisée par `CalculRepasContexte`.
    static func libelleSectionAvecRatio(_ repas: Repas, horairesRepas: HorairesRepas) -> String {
        let section = SectionRepas(heure: repas.heure, horaires: horairesRepas)
        guard let ratio = repas.ratioEffectifPersiste else { return section.titre }
        return "\(section.titre) · 1u/\(Int(ratio.rounded()))g"
    }

    /// Badges d'ajustement affichables (« Sport récent · Course à pied »),
    /// catégorisés (sport vs autre) pour la couleur. Toujours calculés,
    /// jamais utilisés pour filtrer — l'affichage reste honnête même sur un
    /// repas ajusté-sport. Non-`private` : réutilisée par `CalculRepasContexte`.
    static func badgesAjustements(_ repas: Repas) -> [BadgeAjustement] {
        repas.ajustements.map { ajustement in
            let libelle = ajustement.typeSportDetecte.map { "\(ajustement.raison.libelle) · \($0)" }
                ?? ajustement.raison.libelle
            return BadgeAjustement(libelle: libelle, estSport: ajustement.raison == .sportRecent)
        }
    }

    /// Courbe pour affichage — tronquée à 0…180 min pour matcher le domaine
    /// fixe du mini-chart existant (`CarteRepasARevoir`, non modifié ici).
    /// Non-`private` : réutilisée par `CalculRepasContexte`.
    static func courbeAffichage(_ repas: Repas) -> [PointCourbeRepas]? {
        guard case .disponible(let reponse) = repas.etatAnalyse else { return nil }
        return reponse.pointsCgm
            .filter { $0.secondesDepuisRepas >= 0 && $0.secondesDepuisRepas <= 180 * 60 }
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
