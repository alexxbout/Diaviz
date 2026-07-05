//
//  AnalyseBasaleService.swift
//  diaviz
//
//  Created by Alexandre on 27/06/2026.
//

import CryptoKit
import Foundation
import Observation
import SwiftData

/// Service **réel** de l'analyse B1 (détection basale inadaptée) — dérivation
/// branchée sur le hub. Lit les faits bruts (CGM, lente, rapides, repas, sport,
/// pauses) sur la fenêtre 14 nuits, les mappe en value types et délègue
/// l'assemblage à `CalculAnalyseBasale` (calculateur pur).
///
/// Convention « un hub, des dérivations » : aucune analyse n'est persistée. Le
/// contexte est injecté au boot via `.task { demarrer(contexte:) }` ; la
/// `AnalyseBasaleDetail` est recalculée à `recharger()` (après une ingestion).
@Observable
@MainActor
final class AnalyseBasaleService {

    /// Snapshot complet prêt à afficher. Initialisé « vide » (données
    /// insuffisantes) avant le premier chargement.
    private(set) var analyse: AnalyseBasaleDetail

    private var contexte: ModelContext?

    /// `true` une fois `demarrer(contexte:)` appelé — permet à la vue de
    /// distinguer le premier boot d'un simple retour sur la page (re-sync).
    var estDemarre: Bool { contexte != nil }

    init() {
        analyse = CalculAnalyseBasale.analyser(entrees: .vide)
    }

    // MARK: - Boot

    /// Branche le service sur le hub et calcule une première fois. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    /// Recharge les faits bruts depuis le hub et reconstruit l'analyse.
    /// Idempotent : peut être rappelé après une ingestion CGM.
    func recharger() {
        guard let contexte else { return }
        let profil = ProfilService.shared.profil
        let config = ConfigBasale(
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        analyse = CalculAnalyseBasale.analyser(
            entrees: chargerEntrees(contexte: contexte),
            config: config
        )
    }

    // MARK: - Résumé pour la carte sommaire (B1 ligne)

    /// `ResumeAnalyseCoucher` dérivé de l'analyse réelle. B1 reflète le verdict ;
    /// B2 / B3 restent en attente tant que leurs assembleurs ne sont pas branchés.
    var resumeCoucher: ResumeAnalyseCoucher {
        ResumeAnalyseCoucher(
            verdictBasale: analyse.verdict,
            sections: [
                ResumeSousAnalyse(sousAnalyse: .basale, etat: etatBasale, aDuNouveau: estNouvelleTendance),
                ResumeSousAnalyse(sousAnalyse: .glycemie, etat: .enAttente, aDuNouveau: false),
                ResumeSousAnalyse(sousAnalyse: .corrections, etat: .enAttente, aDuNouveau: false),
            ]
        )
    }

    private var etatBasale: EtatSousAnalyse {
        switch analyse.verdict {
        case .adaptee:
            return .resultat(libelle: "Adaptée", ton: .positif)
        case .tropHaute, .tropBasse:
            return .resultat(libelle: "À revoir", ton: .attention)
        case .donneesInsuffisantes:
            return analyse.nuitsAnalysees > 0
                ? .collecte(actuel: analyse.nuitsAnalysees, requis: 3)
                : .enAttente
        }
    }

    // MARK: - Nouvelle tendance (badge navbar + insight accueil)

    /// Clé UserDefaults : signature du dernier verdict B1 **vu** par
    /// l'utilisateur (marqué au moment où il ouvre le détail de l'analyse,
    /// pas juste l'onglet Analyses — un coup d'œil à la liste ne suffit pas).
    private static let cleDerniereSignatureVue = "analyseBasale.derniereSignatureVue"

    /// `true` si le verdict courant (verdict + éventuel « en amélioration »)
    /// diffère du dernier vu — pilote le badge de l'onglet Analyses et le
    /// point « nouveau » sur la ligne « Tendance basale » de la carte
    /// sommaire. Les données insuffisantes ne comptent jamais comme
    /// « nouvelles » (rien à regarder tant qu'il n'y a pas de verdict).
    var estNouvelleTendance: Bool {
        guard analyse.verdict != .donneesInsuffisantes else { return false }
        let vue = UserDefaults.standard.string(forKey: Self.cleDerniereSignatureVue)
        return signatureVerdict != vue
    }

    /// Marque le verdict courant comme vu — appelé quand l'utilisateur ouvre
    /// réellement le détail de l'analyse basale (`DetailAnalyseBasaleVue`).
    func marquerVerdictCommeVu() {
        UserDefaults.standard.set(signatureVerdict, forKey: Self.cleDerniereSignatureVue)
    }

    /// Encodage compact du verdict courant — deux analyses au même verdict
    /// et au même statut « en amélioration » partagent la même signature.
    private var signatureVerdict: String {
        let code: String
        switch analyse.verdict {
        case .adaptee:               code = "adaptee"
        case .tropHaute:             code = "tropHaute"
        case .tropBasse:             code = "tropBasse"
        case .donneesInsuffisantes:  code = "insuffisant"
        }
        return "\(code)|\(analyse.enAmelioration)"
    }

    /// Observation « nouvelle tendance basale » pour la pile d'insights de
    /// l'accueil — `nil` tant qu'il n'y a rien de nouveau à montrer (verdict
    /// déjà vu, ou données insuffisantes). L'`id` est **dérivé de la
    /// signature** (pas aléatoire) : un verdict identique retombe sur le même
    /// identifiant, donc une suppression par l'utilisateur reste valable tant
    /// que le verdict ne change pas, et l'insight réapparaît naturellement dès
    /// que la tendance évolue.
    var insightNouvelleTendance: Insight? {
        guard estNouvelleTendance else { return nil }

        let categorie: CategorieInsight
        let message: String
        let microVisuel: MicroVisuelType
        if analyse.enAmelioration {
            categorie = .positif
            message = "Amélioration observée sur les dernières nuits"
            microVisuel = .grandeIcone(systemName: "arrow.up.forward.circle.fill")
        } else {
            switch analyse.verdict {
            case .tropHaute:
                categorie = .attention
                message = "Basale potentiellement trop élevée"
                microVisuel = .grandNombreAvecFleche(valeur: "\(analyse.nuitsAnalysees) nuits", direction: "arrow.down.right")
            case .tropBasse:
                categorie = .attention
                message = "Basale potentiellement trop faible"
                microVisuel = .grandNombreAvecFleche(valeur: "\(analyse.nuitsAnalysees) nuits", direction: "arrow.up.right")
            case .adaptee:
                categorie = .positif
                message = "Basale stable sur la période"
                microVisuel = .grandeIcone(systemName: "checkmark.circle.fill")
            case .donneesInsuffisantes:
                return nil
            }
        }

        return Insight(
            id: Self.idDeterministe(signatureVerdict),
            categorie: categorie,
            titre: "Tendance nocturne",
            message: message,
            microVisuel: microVisuel,
            lienAnalyse: "tendance-nocturne"
        )
    }

    /// UUID stable dérivé d'une chaîne (SHA-256 tronqué à 16 octets) — pas de
    /// `String.hashValue` ici, qui varie d'un lancement à l'autre (seed
    /// randomisée) et casserait la persistance des insights supprimés.
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

    // MARK: - Accès au hub (mapping @Model → value types)

    private func chargerEntrees(contexte: ModelContext) -> EntreesBasale {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique()
        // CGM / repas / sport / pauses : couvrent les 14 nuits (+ marge zone 1).
        let borneCourte = cal.date(byAdding: .day, value: -15, to: debutCourant) ?? debutCourant
        // Lentes : fenêtre large pour détecter le palier de dose courant et son début.
        let borneDose = cal.date(byAdding: .day, value: -120, to: debutCourant) ?? debutCourant

        let cgm = fetchCGM(contexte, depuis: borneCourte)
        let (lentes, rapides) = fetchInjections(contexte, depuis: borneDose)
        let repas = fetchRepas(contexte, depuis: borneCourte)
        let sports = fetchSports(contexte, depuis: borneCourte)
        let pauses = fetchPauses(contexte, depuis: borneCourte)

        return EntreesBasale(
            lectures: cgm, lentes: lentes, rapides: rapides,
            repas: repas, sports: sports, pauses: pauses
        )
    }

    private func fetchCGM(_ contexte: ModelContext, depuis: Date) -> [(date: Date, valeur: Int)] {
        var d = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= depuis },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        d.propertiesToFetch = [\.date, \.valeur]
        return ((try? contexte.fetch(d)) ?? []).map { (date: $0.date, valeur: $0.valeur) }
    }

    private func fetchInjections(
        _ contexte: ModelContext, depuis: Date
    ) -> (lentes: [(heure: Date, dose: Double)], rapides: [(heure: Date, dose: Double, correction: Bool)]) {
        let d = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.heure >= depuis },
            sortBy: [SortDescriptor(\.heure, order: .forward)]
        )
        let toutes = (try? contexte.fetch(d)) ?? []
        // Le filtre par type d'enum se fait en Swift (fragile dans un #Predicate).
        let lentes = toutes.filter { $0.type == .lente }.map { (heure: $0.heure, dose: $0.dose) }
        let rapides = toutes.filter { $0.type != .lente }.map {
            (heure: $0.heure, dose: $0.dose,
             correction: $0.type == .rapideCorrection || $0.motif == .correction)
        }
        return (lentes, rapides)
    }

    private func fetchRepas(_ contexte: ModelContext, depuis: Date) -> [(heure: Date, glucides: Int)] {
        let d = FetchDescriptor<Repas>(predicate: #Predicate { $0.heure >= depuis })
        return ((try? contexte.fetch(d)) ?? []).map { (heure: $0.heure, glucides: $0.totalGlucides) }
    }

    private func fetchSports(_ contexte: ModelContext, depuis: Date) -> [(debut: Date, dureeMin: Int)] {
        let d = FetchDescriptor<ActiviteSportive>(predicate: #Predicate { $0.dateDebut >= depuis })
        return ((try? contexte.fetch(d)) ?? []).map { (debut: $0.dateDebut, dureeMin: $0.dureeMinutes) }
    }

    private func fetchPauses(_ contexte: ModelContext, depuis: Date) -> [(debut: Date, fin: Date?)] {
        // Peu nombreuses : on récupère tout et on filtre les obsolètes en Swift
        // (les bornes `Date?` sont délicates dans un #Predicate).
        let d = FetchDescriptor<PeriodePause>()
        return ((try? contexte.fetch(d)) ?? [])
            .filter { ($0.fin ?? Date()) >= depuis }
            .map { (debut: $0.debut, fin: $0.fin) }
    }
}

// MARK: - Entrée vide (état initial avant chargement)

extension EntreesBasale {
    /// Entrée sans aucun fait — produit une analyse « données insuffisantes »
    /// cohérente (14 nuits sans données). Sert d'état initial du service.
    static var vide: EntreesBasale {
        EntreesBasale(lectures: [], lentes: [], rapides: [], repas: [], sports: [], pauses: [])
    }
}
