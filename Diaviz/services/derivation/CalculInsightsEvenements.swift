//
//  CalculInsightsEvenements.swift
//  diaviz
//

import CryptoKit
import Foundation
import SwiftUI

/// Cartes d'**événement** de la pile « Nouvelles tendances » : quelque chose
/// vient de se produire ou de devenir consultable (réponse d'un repas, d'une
/// séance, activité à importer, épisode de charge, repas à revoir, données de
/// ratio). Contrairement aux cartes d'état (tendance nocturne, écart de
/// ratio), chacune a une **durée de vie** : passé ce délai elle s'efface seule,
/// sans que l'utilisateur ait à la supprimer.
///
/// Calculateur pur : il reçoit des faits déjà calculés ailleurs et ne relit
/// rien. Chaque carte porte un identifiant déterministe — la supprimer la
/// masque pour de bon, et un nouvel événement (autre repas, autre épisode)
/// produit une nouvelle carte.
///
/// Doc canonique : `docs/analyses/Cartes d'insights accueil — Nouvelles tendances.md`.
nonisolated enum CalculInsightsEvenements {

    // MARK: Durées de vie

    /// Réponse d'un repas ou d'une séance : 24 h après sa disponibilité.
    static let dureeVieReponse: TimeInterval = 24 * 3600
    /// Repas à revoir : seuls ceux pris dans les 48 dernières heures comptent
    /// comme « nouveaux ».
    static let ageMaxRepasARevoir: TimeInterval = 48 * 3600
    /// Données de ratio disponibles : 7 jours après la comparaison.
    static let dureeVieRatio: TimeInterval = 7 * 24 * 3600

    // MARK: Disponibilité d'une réponse

    /// Fenêtre d'observation d'un repas (T+4 h), alignée sur
    /// `AssembleurReponseRepas.finFenetre`.
    static let fenetreRepas: TimeInterval = 4 * 3600
    /// Marge observée après une séance (`ActivitesSportService`).
    static let margeSeance: TimeInterval = 30 * 60
    /// Retard structurel du capteur (~3 h) : la courbe d'une séance n'est
    /// complète qu'après lui.
    static let delaiCapteur: TimeInterval = 3 * 3600

    // MARK: Réponse d'un repas

    static func reponseRepas(
        id: UUID, heure: Date, reponse: ReponseGlycemique,
        seuils: SeuilsGlycemiques, maintenant: Date
    ) -> Insight? {
        let disponibleA = heure.addingTimeInterval(fenetreRepas)
        guard estVivante(depuis: disponibleA, duree: dureeVieReponse, maintenant: maintenant),
              reponse.pointsCgm.count >= 2 else { return nil }

        let points = reponse.pointsCgm.map {
            CourbeInsight.Point(minutes: $0.secondesDepuisRepas / 60, valeur: $0.valeur)
        }
        let courbe = CourbeInsight(
            points: points,
            repere: 0...0,
            repereEstUneBande: false,
            pic: .init(minutes: reponse.tempsPic / 60, valeur: reponse.valeurPic),
            seuils: seuils
        )
        return Insight(
            id: idDeterministe("reponse-repas|\(id.uuidString)"),
            categorie: .reponse,
            titre: "Repas de \(heureCourte(heure))",
            message: "",
            microVisuel: .courbe(courbe),
            lienAnalyse: nil,
            date: disponibleA,
            libelleLien: "Voir la réponse →",
            destination: .detailRepas(id),
            teinte: .indigo
        )
    }

    // MARK: Réponse d'une séance

    static func reponseSeance(
        id: UUID, libelleType: String, debut: Date, fin: Date, dureeMinutes: Int,
        reponse: ReponseGlycemiqueSport, seuils: SeuilsGlycemiques, maintenant: Date
    ) -> Insight? {
        let disponibleA = fin.addingTimeInterval(margeSeance + delaiCapteur)
        guard estVivante(depuis: disponibleA, duree: dureeVieReponse, maintenant: maintenant),
              reponse.pointsCgm.count >= 2 else { return nil }

        let points = reponse.pointsCgm.map {
            CourbeInsight.Point(minutes: $0.secondesDepuisDebut / 60, valeur: $0.valeur)
        }
        let finEffort = fin.timeIntervalSince(debut) / 60
        let courbe = CourbeInsight(
            points: points,
            repere: 0...max(finEffort, Double(dureeMinutes)),
            repereEstUneBande: true,
            pic: points.max { $0.valeur < $1.valeur },
            seuils: seuils
        )
        return Insight(
            id: idDeterministe("reponse-seance|\(id.uuidString)"),
            categorie: .reponse,
            titre: "\(libelleType) de \(heureCourte(debut))",
            message: "",
            microVisuel: .courbe(courbe),
            lienAnalyse: nil,
            date: disponibleA,
            icone: "figure.run",
            libelleLien: "Voir la réponse →",
            destination: .detailSeance(id),
            teinte: .brown
        )
    }

    // MARK: Activité à importer

    struct CandidatImport: Sendable, Equatable {
        let id: UUID
        let libelleType: String
        let icone: String
        let debut: Date
        let fin: Date
    }

    /// Une seule carte pour tous les candidats en attente : elle vit tant
    /// qu'il en reste, et change d'identifiant quand l'ensemble change (une
    /// carte supprimée revient si une nouvelle activité est détectée).
    static func activitesAImporter(_ candidats: [CandidatImport]) -> Insight? {
        guard let recent = candidats.max(by: { $0.fin < $1.fin }) else { return nil }
        let signature = candidats.map(\.id.uuidString).sorted().joined(separator: ",")
        let n = candidats.count
        let quand = recent.debut.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return Insight(
            id: idDeterministe("import|\(signature)"),
            categorie: .action,
            titre: n == 1 ? "Activité à importer" : "\(n) activités à importer",
            // Une ligne : le message n'a de place que pour une.
            message: n == 1
                ? "\(recent.libelleType) · \(quand)"
                : "Dernière : \(recent.libelleType) · \(quand)",
            microVisuel: .grandeIcone(systemName: recent.icone),
            lienAnalyse: nil,
            date: recent.fin,
            icone: "square.and.arrow.down",
            libelleLien: "Importer →",
            destination: .importSport
        )
    }

    // MARK: Nouveaux repas à revoir

    struct OccurrenceARevoir: Sendable, Equatable {
        let idRepasSource: UUID
        let heure: Date
    }

    /// Repas à revoir pris dans les 48 dernières heures. Le jeu d'entrée est
    /// déjà filtré des repas masqués par l'utilisateur.
    static func nouveauxRepasARevoir(_ occurrences: [OccurrenceARevoir], maintenant: Date) -> Insight? {
        let recentes = occurrences.filter {
            $0.heure <= maintenant && maintenant.timeIntervalSince($0.heure) <= ageMaxRepasARevoir
        }
        guard let derniere = recentes.map(\.heure).max() else { return nil }
        let n = recentes.count
        let signature = recentes.map(\.idRepasSource.uuidString).sorted().joined(separator: ",")
        return Insight(
            id: idDeterministe("revoir|\(signature)"),
            categorie: .attention,
            titre: "Repas à revoir",
            message: n == 1
                ? "Un nouveau repas depuis 2 jours"
                : "\(n) nouveaux repas depuis 2 jours",
            microVisuel: .grandNombre(valeur: "\(n)"),
            lienAnalyse: nil,
            date: min(derniere.addingTimeInterval(fenetreRepas), maintenant),
            libelleLien: "Voir les repas →",
            destination: .repasARevoir
        )
    }

    // MARK: Données de ratio disponibles

    /// Une carte par moment dont la comparaison avant/après un changement de
    /// ratio vient de devenir calculable (assez de repas depuis le changement).
    static func donneesRatio(
        _ apercus: [SectionRepas?: ApercuChangementRatio], maintenant: Date
    ) -> [Insight] {
        apercus.compactMap { groupe, apercu -> Insight? in
            guard apercu.comparaison != nil,
                  let disponible = apercu.dateComparaisonDisponible,
                  estVivante(depuis: disponible, duree: dureeVieRatio, maintenant: maintenant)
            else { return nil }
            let libelle = CalculRatioObserve.libelleGroupe(groupe)
            let depuis = apercu.dateChangement.formatted(.dateTime.day().month(.abbreviated))
            return Insight(
                id: idDeterministe("ratio-donnees|\(libelle)|\(Int(apercu.dateChangement.timeIntervalSince1970))"),
                categorie: .action,
                titre: "Ratio",
                message: "\(libelle) · depuis le \(depuis)",
                microVisuel: .grandNombre(valeur: "\(apercu.effectifDepuis) repas"),
                lienAnalyse: nil,
                date: disponible,
                icone: "arrow.left.arrow.right",
                libelleLien: "Voir la comparaison →",
                destination: .ecartRatio
            )
        }
    }

    // MARK: Épisode de charge

    static func episodeCharge(_ synthese: SyntheseEpisodesCharge?) -> Insight? {
        guard let episode = synthese?.enCours,
              CalculEpisodesCharge.estNouvelEpisode(episode, precedent: synthese?.precedent),
              let niveau = episode.niveau else { return nil }
        let jours = episode.faits.jours
        return Insight(
            id: idDeterministe("episode|\(Int(episode.debut.timeIntervalSince1970))"),
            categorie: .informatif,
            titre: "Charge",
            message: "Nouvel épisode · \(niveau.libelleEpisode) · \(jours) jour\(jours > 1 ? "s" : "")",
            microVisuel: .grandeIcone(systemName: "flame.fill"),
            lienAnalyse: nil,
            date: episode.debut,
            icone: "flame.fill",
            libelleLien: "Voir l'épisode →",
            destination: .chargeEtGlycemie
        )
    }

    // MARK: Ordre de la pile

    /// L'alerte d'abord, puis les événements du plus récent au plus ancien,
    /// puis les cartes d'état. Aucun plafond : tout est supprimable.
    static func ordonner(alerte: Insight?, evenements: [Insight], etats: [Insight]) -> [Insight] {
        let evenementsTries = evenements.sorted {
            let a = $0.date ?? .distantPast, b = $1.date ?? .distantPast
            return a != b ? a > b : $0.id.uuidString < $1.id.uuidString
        }
        return [alerte].compactMap { $0 } + evenementsTries + etats
    }

    // MARK: Outils

    private static func estVivante(depuis disponible: Date, duree: TimeInterval, maintenant: Date) -> Bool {
        maintenant >= disponible && maintenant.timeIntervalSince(disponible) <= duree
    }

    private static func heureCourte(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// UUID stable dérivé d'une chaîne (SHA-256 tronqué à 16 octets) — même
    /// pattern que les autres insights, jamais `hashValue`.
    static func idDeterministe(_ chaine: String) -> UUID {
        let o = Array(SHA256.hash(data: Data(chaine.utf8)).prefix(16))
        return UUID(uuid: (
            o[0], o[1], o[2], o[3], o[4], o[5], o[6], o[7],
            o[8], o[9], o[10], o[11], o[12], o[13], o[14], o[15]
        ))
    }
}

nonisolated private extension NiveauChargeActive {
    /// Niveau en un mot, pour la ligne unique d'une carte.
    var libelleEpisode: String {
        switch self {
        case .basse:   "basse"
        case .normale: "référence"
        case .haute:   "haute"
        }
    }
}
