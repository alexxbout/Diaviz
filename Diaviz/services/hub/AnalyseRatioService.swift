//
//  AnalyseRatioService.swift
//  diaviz
//

import CryptoKit
import Foundation
import Observation
import SwiftData

/// Service **réel** du mining du ratio observé (cœur ML de R1) — cache en
/// mémoire, recalculé sur mutation du hub plutôt qu'à chaque frappe de
/// saisie. Lit directement `RepasService.repas` (déjà chargé et annoté, pas
/// de fetch SwiftData séparé) et délègue à `CalculRatioObserve` (pur).
///
/// Pattern de démarrage aligné sur `AnalyseBasaleService` : `analyse` prêt à
/// l'affichage dès l'init (état « données insuffisantes »), recalculé via
/// `recalculer(depuis:)` après chaque mutation connue du hub.
/// Ce qu'affiche le bloc « depuis le changement de ratio » d'une section :
/// date + effectif toujours peuplés (alimentent le badge même sous le seuil
/// de comparaison), `comparaison` `nil` tant que l'effectif après changement
/// n'atteint pas `CalculDoseRatioChangement.effectifMinimalComparaison`.
nonisolated struct ApercuChangementRatio: Sendable, Equatable {
    let dateChangement: Date
    let effectifDepuis: Int
    let comparaison: ComparaisonChangementRatio?
}

/// Ventilation des repas d'un moment de la journée entre ce qui alimente
/// réellement le mining R1 et ce qui en est écarté, **avec la raison**.
///
/// La carte de saisie ne disposait que du total retenu, et disait donc
/// « aucun repas encore analysé sur ce moment » aussi bien quand rien n'avait
/// été saisi que quand quinze dîners attendaient leurs glycémies ou avaient
/// été écartés pour cause d'ajustement. Quatre situations sans rapport sous
/// une seule phrase : l'utilisateur en concluait que ses saisies étaient
/// ignorées.
///
/// Chaque repas est compté **une seule fois**, dans la première catégorie qui
/// le capture — l'ordre suit exactement celui des `guard` de `mapperEntrees`.
/// Un repas à la fois ajusté et antérieur au changement de ratio compte donc
/// comme « ajusté », jamais dans les deux.
nonisolated struct RepartitionRepasMoment: Sendable, Equatable {
    /// Repas retenus par le mining — le seul décompte qui alimente une
    /// comparaison de ratio.
    var analyses = 0
    /// Fenêtre CGM pas encore complète (T+4h, plus le délai capteur).
    var enAttente = 0
    /// CGM absent ou couverture insuffisante sur la fenêtre.
    var donneesManquantes = 0
    /// Repas sans dose d'insuline : réponse glycémique non interprétable.
    var sansInjection = 0
    /// Dose volontairement déviée du ratio (`Repas.ajustements`).
    var ajustes = 0
    /// Événement en texte libre, jamais interprété par une analyse.
    var contexteLibre = 0
    /// Un ratio post-sport était en vigueur au moment du repas : la dose a été
    /// jugée sur **ce** ratio à la saisie, la comparer au ratio du moment
    /// mesurerait un écart qui n'existe pas.
    var ratioSportEnVigueur = 0
    /// Toggle « Exclure des analyses » posé à la main sur le repas.
    var exclusManuellement = 0
    /// Antérieurs au dernier changement de ratio de ce moment : plus
    /// comparables au ratio actuel.
    var avantChangementRatio = 0
    /// Date de ce changement de ratio, quand il y en a eu un.
    var dateChangementRatio: Date?
    /// Nom du moment au singulier (« dîner », « en-cas », « repas » en mode
    /// ratio unique) — porté ici parce que seul le service connaît la section
    /// réelle, et que le libellé du profil vaut « post-musculation » dès qu'un
    /// ratio sport prend la main.
    var libelleMoment = "repas"
    /// Pluriel du même libellé (« dîners », « en-cas » invariable).
    var libelleMomentPluriel = "repas"

    /// Total de repas rattachés à ce moment, toutes situations confondues.
    var total: Int {
        analyses + enAttente + donneesManquantes + sansInjection
            + ajustes + contexteLibre + exclusManuellement + avantChangementRatio
            + ratioSportEnVigueur
    }

    /// Repas mis de côté sur décision de l'utilisateur (ajustement, contexte
    /// libre, exclusion manuelle) — par opposition aux repas simplement pas
    /// encore analysables.
    var ecartes: Int { ajustes + contexteLibre + exclusManuellement }

    /// Classe un repas sans verdict exploitable d'après son `EtatAnalyse`
    /// (dérivation `@Transient` posée par `RepasService` sur les repas
    /// récents). Sans état — repas trop ancien pour être ré-annoté —, on
    /// retombe sur « données manquantes » : c'est ce qui est vrai côté
    /// mining, la courbe n'existe plus en mémoire.
    mutating func compterVerdictIndisponible(etat: EtatAnalyse?) {
        switch etat {
        case .enAttente:     enAttente += 1
        case .sansInjection: sansInjection += 1
        default:             donneesManquantes += 1
        }
    }
}

@Observable
@MainActor
final class AnalyseRatioService {

    private(set) var analyse: AnalyseRatioObserve = .vide

    /// Comparaison dose/verdict avant-après le dernier changement de ratio,
    /// par section — seulement les sections dont le ratio a déjà changé une
    /// fois (`nil` = jamais modifié, rien à comparer). Alimente le bloc
    /// « depuis le changement de ratio » de `SheetEcartRatio`.
    private(set) var apercusChangementRatio: [SectionRepas?: ApercuChangementRatio] = [:]

    /// Ventilation des repas par moment — dit à la carte de saisie *pourquoi*
    /// un moment n'a pas (encore) de repas analysé.
    private(set) var repartitions: [SectionRepas?: RepartitionRepasMoment] = [:]

    /// Recalcule depuis les repas déjà chargés/annotés par `RepasService` —
    /// aucun fetch CGM ni régression ici, juste un mapping en value types et
    /// un comptage : volume trivial (quelques milliers de repas au grand
    /// maximum), pas besoin de `Task.detached`.
    /// - Parameter activites: séances sportives du hub, nécessaires pour
    ///   écarter les repas où un **ratio post-sport** faisait foi. Injectées
    ///   plutôt que fetchées ici : le service reste sans `ModelContext`, et
    ///   le mapping garde des entrées entièrement contrôlables en test.
    /// Variante appelée par les vues : récupère les séances du hub avant de
    /// déléguer. Le volume est trivial (quelques centaines de séances au
    /// grand maximum), pas de bornage nécessaire — et en borner une fenêtre
    /// risquerait de rater une séance couvrant un repas ancien.
    func recalculer(depuis repas: [Repas], contexte: ModelContext?) {
        let activites = contexte.flatMap {
            try? $0.fetch(FetchDescriptor<ActiviteSportive>())
        } ?? []
        recalculer(depuis: repas, activites: activites)
    }

    func recalculer(depuis repas: [Repas], activites: [ActiviteSportive] = []) {
        let profil = ProfilService.shared.profil
        var ventilation: [SectionRepas?: RepartitionRepasMoment] = [:]
        let entrees = mapperEntrees(repas, activites: activites, profil: profil, repartitions: &ventilation)
        analyse = CalculRatioObserve.analyser(entrees: entrees)
        apercusChangementRatio = construireApercusChangementRatio(repas, profil: profil)
        repartitions = ventilation
    }

    /// Explose chaque repas exploitable en une `EntreeRatioRepas` (une par
    /// repas — plus d'explosion multi-groupe depuis que les ajustements sont
    /// exclus du mining, voir garde ci-dessous).
    ///
    /// Ventile au passage **chaque repas écarté** dans `repartitions`, avec la
    /// raison : la boucle connaissait déjà ce motif à chaque `continue`, elle
    /// l'oubliait simplement. C'est ce qui permet à la carte de saisie de dire
    /// « 4 dîners en attente des glycémies » plutôt que « aucun repas analysé ».
    private func mapperEntrees(
        _ repas: [Repas], activites: [ActiviteSportive], profil: ProfilUtilisateur,
        repartitions: inout [SectionRepas?: RepartitionRepasMoment]
    ) -> [EntreeRatioRepas] {
        var entrees: [EntreeRatioRepas] = []

        for r in repas {
            // Le groupe est déterminé avant toute exclusion : un repas écarté
            // doit quand même être compté dans le moment auquel il appartient.
            let sectionReelle = SectionRepas(heure: r.heure, horaires: profil.horairesRepas)
            let groupe = profil.modeRatio == .unique ? nil : sectionReelle
            var repartition = repartitions[groupe] ?? Self.repartitionVierge(groupe: groupe)
            defer { repartitions[groupe] = repartition }

            // Exclusions du mining, toutes au même niveau :
            // - toggle « Exclure des analyses » ;
            // - événement / contexte libre non structuré (jamais interprété) ;
            // - ajustement intentionnel (sport, hypo…) : la dose appliquée
            //   dévie *volontairement* du ratio de base, comparer les deux
            //   ne mesure rien — voir doc R1 « Ajustements exclus du mining ».
            guard !r.exclureDesAnalyses else { repartition.exclusManuellement += 1; continue }
            guard !r.aUnEvenement else { repartition.contexteLibre += 1; continue }
            guard r.ajustements.isEmpty else { repartition.ajustes += 1; continue }
            // Un ratio post-sport en vigueur écarte le repas au même titre
            // qu'un ajustement manuel : `InsightsService` a jugé la dose sur
            // ce ratio-là à la saisie, la comparer ici au ratio du moment
            // classerait un repas correctement dosé comme un écart.
            guard !ratioSportEnVigueur(a: r.heure, activites: activites, profil: profil) else {
                repartition.ratioSportEnVigueur += 1
                continue
            }

            guard let verdict = r.verdictPersiste, verdict != .indetermine,
                  r.totalGlucides > 0 else {
                repartition.compterVerdictIndisponible(etat: r.etatAnalyse)
                continue
            }
            let doseCouvrante = r.totalInsuline - (r.doseCorrection ?? 0)
            guard doseCouvrante > 0 else { repartition.sansInjection += 1; continue }

            // Un repas antérieur au dernier changement du ratio de cette
            // section n'est plus comparable au ratio actuel — voir
            // `dateChangement`.
            let changement = dateChangement(section: sectionReelle, profil: profil)
            repartition.dateChangementRatio = changement
            guard r.heure >= (changement ?? .distantPast) else {
                repartition.avantChangementRatio += 1
                continue
            }

            guard let ratioConfigure = InsightsService.ratioConfigure(section: sectionReelle, profil: profil),
                  ratioConfigure > 0 else {
                // Aucun ratio configuré pour ce moment : rien à comparer, et
                // la carte de validation ne s'affiche pas non plus.
                continue
            }

            let doseSuggeree = Double(r.totalGlucides) / ratioConfigure

            repartition.analyses += 1
            entrees.append(EntreeRatioRepas(
                id: r.id, groupe: groupe, doseAppliquee: doseCouvrante, doseSuggeree: doseSuggeree,
                glucides: r.totalGlucides, verdict: verdict,
                raisonMauvais: r.raisonMauvaisPersistee
            ))
        }

        return entrees
    }

    /// Répartition vide déjà porteuse des libellés du moment — c'est le
    /// service qui connaît la section réelle, la vue n'a plus qu'à composer sa
    /// phrase.
    private static func repartitionVierge(groupe: SectionRepas?) -> RepartitionRepasMoment {
        var vierge = RepartitionRepasMoment()
        guard let groupe else { return vierge } // mode ratio unique : « repas »
        let singulier = groupe.titre.lowercased()
        vierge.libelleMoment = singulier
        // « en-cas » est invariable, les autres prennent un s.
        vierge.libelleMomentPluriel = singulier.hasSuffix("s") ? singulier : singulier + "s"
        return vierge
    }

    // MARK: - Comparaison avant/après changement de ratio

    /// Explose chaque repas exploitable en `EntreeDoseChangement`, groupé par
    /// section — **tout** l'historique, sans borne de date, contrairement à
    /// `mapperEntrees`. Mêmes exclusions (pause, contexte libre, ajustement,
    /// verdict indéterminé, dose nulle) que `mapperEntrees`, dupliquées
    /// intentionnellement : les deux mappers produisent des value types
    /// différents (celui-ci n'a pas besoin du ratio configuré, donc pas de
    /// dose suggérée à calculer), les faire dépendre l'un de l'autre
    /// couplerait deux usages qui doivent pouvoir diverger séparément.
    private func mapperEntreesDoseChangement(
        _ repas: [Repas], profil: ProfilUtilisateur
    ) -> [SectionRepas?: [EntreeDoseChangement]] {
        var parGroupe: [SectionRepas?: [EntreeDoseChangement]] = [:]
        for r in repas {
            guard !r.exclureDesAnalyses, !r.aUnEvenement, r.ajustements.isEmpty else { continue }
            guard let verdict = r.verdictPersiste, verdict != .indetermine, r.totalGlucides > 0 else { continue }
            let doseCouvrante = r.totalInsuline - (r.doseCorrection ?? 0)
            guard doseCouvrante > 0 else { continue }

            let sectionReelle = SectionRepas(heure: r.heure, horaires: profil.horairesRepas)
            let groupe = profil.modeRatio == .unique ? nil : sectionReelle
            parGroupe[groupe, default: []].append(
                EntreeDoseChangement(heure: r.heure, doseAppliquee: doseCouvrante, verdict: verdict)
            )
        }
        return parGroupe
    }

    /// Un `ApercuChangementRatio` par section dont le ratio a déjà changé —
    /// absente du dictionnaire pour une section jamais modifiée (rien à
    /// comparer, pas d'entrée « nulle » à filtrer côté vue).
    private func construireApercusChangementRatio(
        _ repas: [Repas], profil: ProfilUtilisateur
    ) -> [SectionRepas?: ApercuChangementRatio] {
        let entreesParGroupe = mapperEntreesDoseChangement(repas, profil: profil)
        var resultat: [SectionRepas?: ApercuChangementRatio] = [:]
        for (groupe, entrees) in entreesParGroupe {
            guard let date = dateChangementEffective(groupe: groupe, profil: profil) else { continue }
            let effectifDepuis = entrees.filter { $0.heure >= date }.count
            resultat[groupe] = ApercuChangementRatio(
                dateChangement: date,
                effectifDepuis: effectifDepuis,
                comparaison: CalculDoseRatioChangement.comparer(entrees: entrees, dateChangement: date)
            )
        }
        return resultat
    }

    /// Date de changement pour un groupe potentiellement `nil` (mode ratio
    /// unique) — même repli que `CarteAnalyseRatio.dateChangement(_:)`.
    private func dateChangementEffective(groupe: SectionRepas?, profil: ProfilUtilisateur) -> Date? {
        guard let groupe else { return profil.datesChangementRatioEffectives.unique }
        return dateChangement(section: groupe, profil: profil)
    }

    /// `true` si une séance s'est terminée dans la fenêtre d'effet configurée
    /// **et** que son type de sport a un ratio post-sport renseigné.
    ///
    /// Les deux conditions comptent : sans ratio configuré pour ce sport,
    /// `InsightsService` laisse la main au ratio du moment à la saisie, donc
    /// le repas reste légitimement comparable et ne doit pas être écarté.
    /// Mêmes bornes que `InsightsService.sportRecent` — séance encore en cours
    /// incluse, `dateFin` comme référence (elle réintègre les pauses).
    private func ratioSportEnVigueur(
        a heure: Date, activites: [ActiviteSportive], profil: ProfilUtilisateur
    ) -> Bool {
        let ratios = profil.ratiosSportEffectifs
        let fenetre = ratios.fenetreEffetHeures * 3600
        return activites.contains { activite in
            guard activite.dateDebut <= heure else { return false }
            let depuisFin = heure.timeIntervalSince(activite.dateFin)
            guard depuisFin <= fenetre else { return false }
            guard let grammes = ratios.ratio(pour: activite.type), grammes > 0 else { return false }
            return true
        }
    }

    /// Date du dernier changement du ratio applicable à cette section — même
    /// règle de repli que `InsightsService.ratioConfigure` (nuit retombe sur
    /// dîner, ils partagent le même ratio donc la même date). `nil` = jamais
    /// changé, tout l'historique reste éligible.
    ///
    /// Exposée (non privée) pour que l'accueil puisse **dire** qu'un compteur
    /// est reparti de zéro : sans ça le filtrage appliqué ici est invisible
    /// côté UI, et un moment qui avait 25 repas retombe à 2 sans explication.
    func dateChangement(section: SectionRepas, profil: ProfilUtilisateur) -> Date? {
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
