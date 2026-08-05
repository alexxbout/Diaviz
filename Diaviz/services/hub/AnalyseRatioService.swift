//
//  AnalyseRatioService.swift
//  diaviz
//

import CryptoKit
import Foundation
import Observation

/// Service **réel** du mining du ratio observé (cœur ML de R1) — cache en
/// mémoire, recalculé sur mutation du hub plutôt qu'à chaque frappe de
/// saisie. Lit directement `RepasService.repas` (déjà chargé et annoté, pas
/// de fetch SwiftData séparé) et délègue à `CalculRatioObserve` (pur).
///
/// Pattern de démarrage aligné sur `AnalyseBasaleService` : `analyse` prêt à
/// l'affichage dès l'init (état « données insuffisantes »), recalculé via
/// `recalculer(depuis:)` après chaque mutation connue du hub.
@Observable
@MainActor
final class AnalyseRatioService {

    private(set) var analyse: AnalyseRatioObserve = .vide

    /// Recalcule depuis les repas déjà chargés/annotés par `RepasService` —
    /// aucun fetch CGM ni régression ici, juste un mapping en value types et
    /// un comptage : volume trivial (quelques milliers de repas au grand
    /// maximum), pas besoin de `Task.detached`.
    func recalculer(depuis repas: [Repas]) {
        let profil = ProfilService.shared.profil
        let entrees = mapperEntrees(repas, profil: profil)
        analyse = CalculRatioObserve.analyser(entrees: entrees)
    }

    /// Explose chaque repas exploitable en une `EntreeRatioRepas` (une par
    /// repas — plus d'explosion multi-groupe depuis que les ajustements sont
    /// exclus du mining, voir garde ci-dessous).
    private func mapperEntrees(_ repas: [Repas], profil: ProfilUtilisateur) -> [EntreeRatioRepas] {
        var entrees: [EntreeRatioRepas] = []

        for r in repas {
            // Exclusions du mining, toutes au même niveau :
            // - toggle « Exclure des analyses » ;
            // - contexte libre non structuré (jamais interprété) ;
            // - ajustement intentionnel (sport, hypo…) : la dose appliquée
            //   dévie *volontairement* du ratio de base, comparer les deux
            //   ne mesure rien — voir doc R1 « Ajustements exclus du mining ».
            guard !r.exclureDesAnalyses, r.contexteLibre == nil, r.ajustements.isEmpty else { continue }
            guard let verdict = r.verdictPersiste, verdict != .indetermine,
                  r.totalGlucides > 0 else { continue }
            let doseCouvrante = r.totalInsuline - (r.doseCorrection ?? 0)
            guard doseCouvrante > 0 else { continue }

            let sectionReelle = SectionRepas(heure: r.heure, horaires: profil.horairesRepas)

            // Un repas antérieur au dernier changement du ratio de cette
            // section n'est plus comparable au ratio actuel — voir
            // `dateChangement`.
            let borne = dateChangement(section: sectionReelle, profil: profil) ?? .distantPast
            guard r.heure >= borne else { continue }

            guard let ratioConfigure = InsightsService.ratioConfigure(section: sectionReelle, profil: profil),
                  ratioConfigure > 0 else { continue }

            let doseSuggeree = Double(r.totalGlucides) / ratioConfigure
            let groupe = profil.modeRatio == .unique ? nil : sectionReelle

            entrees.append(EntreeRatioRepas(
                groupe: groupe, doseAppliquee: doseCouvrante, doseSuggeree: doseSuggeree,
                glucides: r.totalGlucides, verdict: verdict
            ))
        }

        return entrees
    }

    /// Date du dernier changement du ratio applicable à cette section — même
    /// règle de repli que `InsightsService.ratioConfigure` (nuit retombe sur
    /// dîner, ils partagent le même ratio donc la même date). `nil` = jamais
    /// changé, tout l'historique reste éligible.
    private func dateChangement(section: SectionRepas, profil: ProfilUtilisateur) -> Date? {
        let dates = profil.datesChangementRatioEffectives
        switch profil.modeRatio {
        case .unique:
            return dates.unique
        case .parMoment:
            switch section {
            case .petitDejeuner: return dates.petitDejeuner
            case .dejeuner:      return dates.dejeuner
            case .enCas:         return dates.gouter
            case .diner, .nuit:  return dates.diner
            }
        }
    }

    // MARK: - Insight accueil

    /// Observation « écart de ratio détecté » pour la pile d'insights de
    /// l'accueil — `nil` tant qu'aucun groupe n'a d'écart significatif. Parmi
    /// les groupes concernés, celui à l'écart le plus marqué est retenu (un
    /// seul, pas une carte par groupe). Jamais une dose à utiliser : la
    /// formulation reste factuelle, mêmes dénominateurs bruts que la carte
    /// Validation ratio de la saisie.
    ///
    /// `id` **dérivé de la signature** (groupe + tranche optimale), pas
    /// aléatoire — même pattern que `AnalyseBasaleService.insightNouvelleTendance` :
    /// un écart identique retombe sur le même identifiant, donc une
    /// suppression par l'utilisateur reste valable tant que l'écart ne
    /// change pas.
    var insightEcartDetecte: Insight? {
        let candidats = analyse.sections.compactMap { section -> (SectionRepas?, EcartRatioObserve)? in
            guard let ecart = section.ecart else { return nil }
            return (section.groupe, ecart)
        }
        guard let (groupe, ecart) = candidats.max(by: {
            $0.1.tauxOptimal - $0.1.tauxConfigure < $1.1.tauxOptimal - $1.1.tauxConfigure
        }) else { return nil }

        let optimal = Int((ecart.tauxOptimal * 100).rounded())
        let configure = Int((ecart.tauxConfigure * 100).rounded())
        let libelleGroupe = CalculRatioObserve.libelleGroupe(groupe)
        let signature = "\(libelleGroupe)|\(ecart.trancheOptimale.rawValue)"

        return Insight(
            id: Self.idDeterministe(signature),
            categorie: .informatif,
            titre: libelleGroupe,
            message: "Tes repas à \(ecart.trancheOptimale.libelle) ont \(optimal) % de bons résultats, "
                + "contre \(configure) % à ton ratio actuel.",
            microVisuel: .grandNombre(valeur: "\(optimal) %"),
            lienAnalyse: nil
        )
    }

    /// UUID stable dérivé d'une chaîne (SHA-256 tronqué à 16 octets) — même
    /// pattern que `AnalyseBasaleService.idDeterministe`, pas de
    /// `String.hashValue` qui varie d'un lancement à l'autre.
    private static func idDeterministe(_ chaine: String) -> UUID {
        let empreinte = SHA256.hash(data: Data(chaine.utf8))
        let octets = Array(empreinte.prefix(16))
        return UUID(uuid: (
            octets[0], octets[1], octets[2], octets[3],
            octets[4], octets[5], octets[6], octets[7],
            octets[8], octets[9], octets[10], octets[11],
            octets[12], octets[13], octets[14], octets[15]
        ))
    }
}
