//
//  CalculRepasIsoles.swift
//  diaviz
//

import Foundation

/// Remonte les repas récents **hors mining** dont le verdict est mauvais —
/// contexte libre non structuré (`Repas.contexteLibre`) et/ou ajustement
/// intentionnel (`Repas.ajustements`, sport récent, hypo avant repas…).
/// Alimente la section accueil « Repas à revoir » aux côtés des repas
/// récurrents (`CalculRepasARevoir`).
///
/// Distinct de `CalculRepasARevoir` : ni le texte libre ni un ajustement ne
/// sont une composition recomptable — pas de recherche de récurrence ni de
/// nuage de courbes passées, chaque repas isolé est montré seul (occurrence
/// unique), avec sa vraie courbe CGM. **Aucun seuil de données** : ce n'est
/// pas une inférence statistique, juste la remontée d'un fait isolé.
///
/// Ces deux catégories sont exclues du mining R1 (`CalculRatioObserve`) et du
/// regroupement composition de `CalculRepasARevoir` — voir
/// `Repas.contexteLibre`/`Repas.ajustements` et `AnalyseRatioService.mapperEntrees`.
/// Un repas peut porter les deux à la fois (contexte + ajustement) : une
/// seule carte, les deux blocs de badges s'affichent côte à côte.
nonisolated enum CalculRepasIsoles {

    /// Même fenêtre que `CalculRepasARevoir` : au-delà, plus de courbe CGM en
    /// mémoire (`etatAnalyse` transient, borné par `RepasService`).
    static let fenetreJours = CalculRepasARevoir.fenetreJours
    static let maxCartes = 10

    static func analyser(
        repas: [Repas],
        injections: [Injection] = [],
        activites: [ActiviteSportive] = [],
        horairesRepas: HorairesRepas,
        seuils: SeuilsGlycemiques = SeuilsGlycemiques(),
        idsMasques: Set<UUID> = [],
        maintenant: Date = Date()
    ) -> [RepasARevoir] {
        let borne = maintenant.addingTimeInterval(-Double(fenetreJours) * 86_400)

        let cartes = repas.compactMap { r -> RepasARevoir? in
            guard r.heure >= borne, !r.exclureDesAnalyses,
                  r.contexteLibre != nil || !r.ajustements.isEmpty else { return nil }
            guard case .disponible(let reponse) = r.etatAnalyse, reponse.verdict == .mauvais else { return nil }
            guard let courbe = CalculRepasARevoir.courbeAffichage(r) else { return nil }

            // Même logique que CalculRepasARevoir : événement calculé sur la
            // courbe complète (pas tronquée à 180 min), hypo prioritaire sur pic.
            let postRepas = reponse.pointsCgm.filter { $0.secondesDepuisRepas >= 0 }
            let pointBas = postRepas.min { $0.valeur < $1.valeur }
            let estHypo = (pointBas?.valeur ?? .greatestFiniteMagnitude) < seuils.hypoglycemie
            let evenementMinutes = estHypo
                ? Int((pointBas?.secondesDepuisRepas ?? 0) / 60)
                : Int(reponse.tempsPic / 60)
            let evenementValeur = estHypo ? (pointBas?.valeur ?? 0) : reponse.valeurPic

            return RepasARevoir(
                aliments: r.aliments,
                nombreOccurrences: 1,
                pointsOccurrencesPassees: [],
                pointsDerniereFois: courbe,
                evenementMinutes: evenementMinutes,
                evenementValeur: evenementValeur,
                estHypo: estHypo,
                glucidesMin: r.totalGlucides,
                glucidesMax: r.totalGlucides,
                libelleSection: SectionRepas(heure: r.heure, horaires: horairesRepas).titre,
                badgesAjustements: CalculRepasARevoir.badgesAjustements(r),
                contexteAffiche: r.contexteLibre.map { r.contexteNormalise ?? $0 },
                ratioApplique: r.ratioEffectifPersiste,
                evenements: CalculRepasARevoir.evenements(
                    pour: r, injections: injections, activites: activites, tousRepas: repas
                ),
                heureDerniereOccurrence: r.heure,
                idRepasSource: r.id
            )
        }

        // Voir CalculRepasARevoir.analyser : masquage par occurrence précise
        // (id du repas isolé), pas par groupe — ici chaque carte EST déjà une
        // occurrence unique, donc aucune ambiguïté de récurrence à gérer.
        let visibles = cartes.filter { !idsMasques.contains($0.idRepasSource) }

        return visibles
            .sorted(by: CalculRepasARevoir.plusSevereEnPremier)
            .prefix(maxCartes)
            .map { $0 }
    }
}
