//
//  CalculRepasContexte.swift
//  diaviz
//

import Foundation

/// Remonte les repas récents portant un **contexte libre** (`Repas.contexteLibre`,
/// ex. « je prends la voiture ») dont le verdict est mauvais — alimente la
/// section accueil « Repas avec contexte ».
///
/// Distinct de `CalculRepasARevoir` : un texte libre n'est pas structuré, donc
/// pas de recherche de récurrence ni de nuage de courbes passées — chaque
/// repas contextualisé est montré isolément (occurrence unique), avec sa
/// vraie courbe CGM. Aucun seuil de données (`donneesMinimales`) : ce n'est
/// pas une inférence statistique, juste la remontée d'un fait isolé.
///
/// Ces repas sont exclus du mining R1 (`CalculRatioObserve`) et du
/// regroupement composition de `CalculRepasARevoir` — voir `Repas.contexteLibre`.
nonisolated enum CalculRepasContexte {

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
            guard r.heure >= borne, !r.exclureDesAnalyses, let contexte = r.contexteLibre else { return nil }
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
                contexteAffiche: r.contexteNormalise ?? contexte,
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
