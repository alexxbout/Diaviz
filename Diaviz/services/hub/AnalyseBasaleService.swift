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

    /// `true` pendant le recalcul — pilote le loader de la page Analyses.
    /// La donnée affichée reste l'ancien `analyse` pendant ce temps
    /// (dégradation gracieuse, pas d'écran vide).
    private(set) var enCalcul = false

    private var contexte: ModelContext?

    /// `true` une fois `demarrer(contexte:)` appelé — permet à la vue de
    /// distinguer le premier boot d'un simple retour sur la page (re-sync).
    var estDemarre: Bool { contexte != nil }

    init() {
        analyse = CalculAnalyseBasale.analyser(entrees: .vide)
    }

    // MARK: - Boot

    /// Branche le service sur le hub et calcule une première fois. Idempotent.
    func demarrer(contexte: ModelContext) async {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        await recharger()
    }

    /// Recharge les faits bruts depuis le hub et reconstruit l'analyse.
    /// Idempotent : peut être rappelé après une ingestion CGM.
    ///
    /// Lecture (`LecteurHub`) et assemblage (`CalculAnalyseBasale.analyser`,
    /// pur) tournent hors du thread principal : l'interface reste libre, le
    /// dernier résultat restant affiché pendant ce temps.
    func recharger() async {
        guard let contexte else { return }
        enCalcul = true
        let profil = ProfilService.shared.profil
        var config = ConfigBasale(
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        config.seuilRepasCopieux = profil.preferencesAvancees.seuilRepasCopieuxNuit
            ?? ConfigBasale.seuilRepasCopieuxParDefaut
        config.classementsManuels = profil.preferencesAvancees.classementsNuits ?? [:]
        config.seuilHypo = Int(profil.seuilsGlycemiques.hypoglycemie)
        config.seuilHyper = Int(profil.seuilsGlycemiques.hyperglycemie)
        let entrees = await LecteurHub.lire(container: contexte.container) { Self.chargerEntrees(contexte: $0) }
        analyse = await Task.detached(priority: .userInitiated) {
            CalculAnalyseBasale.analyser(entrees: entrees, config: config)
        }.value
        enCalcul = false
    }

    // MARK: - Résumé pour la carte sommaire

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

    /// `ResumeAnalyseCoucher` complet — B1 reflète le verdict, la ligne
    /// « Hypos au coucher » reflète l'état réel de la fusion B2+B3 fournie
    /// par les services dédiés.
    func resumeCoucher(endormissement: AnalyseEndormissement, corrections: AnalyseCorrections) -> ResumeAnalyseCoucher {
        ResumeAnalyseCoucher(
            verdictBasale: analyse.verdict,
            sections: [
                ResumeSousAnalyse(sousAnalyse: .basale, etat: etatBasale, aDuNouveau: estNouvelleTendance),
                ResumeSousAnalyse(sousAnalyse: .hyposCoucher,
                                  etat: etatHyposCoucher(endormissement: endormissement, corrections: corrections),
                                  aDuNouveau: false),
            ]
        )
    }

    /// Seuil minimal de soirs analysés pour un premier aperçu exploitable
    /// (cadrage B2 : « 10 nuits »).
    private static let soirsRequisHyposCoucher = 10

    /// État glance de la ligne fusionnée « Hypos au coucher » : hypos B2
    /// (endormissement) + sur-corrections B3, sur la population totale.
    private func etatHyposCoucher(
        endormissement: AnalyseEndormissement, corrections: AnalyseCorrections
    ) -> EtatSousAnalyse {
        let totalSoirs = endormissement.nuits.count + corrections.nombre
        let hypos = endormissement.nombreHypos
            + corrections.corrections.filter { $0.issue == .surCorrection }.count
        guard totalSoirs >= Self.soirsRequisHyposCoucher else {
            return totalSoirs == 0
                ? .enAttente
                : .collecte(actuel: totalSoirs, requis: Self.soirsRequisHyposCoucher)
        }
        return hypos > 0
            ? .resultat(libelle: "\(hypos) hypo\(hypos > 1 ? "s" : "")", ton: .attention)
            : .resultat(libelle: "Aucune récente", ton: .positif)
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

    /// Marque comme vu le verdict **réellement affiché** par
    /// `DetailAnalyseBasaleVue` — appelé avec le snapshot figé que la page a
    /// reçu au push, pas avec `self.analyse` en direct.
    ///
    /// `AnalysesVue` relance un `recharger()` à chaque arrivée sur l'onglet ;
    /// si ce recalcul se termine juste après l'ouverture du détail, `analyse`
    /// (en direct) peut changer de signature alors que la page affichait déjà
    /// l'ancienne — marquer d'après le service live rendait le badge "vu"
    /// caduc dans la foulée. Marquer d'après ce que l'utilisateur a
    /// effectivement sous les yeux élimine cette course.
    func marquerVerdictCommeVu(pour analyseAffichee: AnalyseBasaleDetail) {
        UserDefaults.standard.set(Self.signature(pour: analyseAffichee), forKey: Self.cleDerniereSignatureVue)
    }

    /// Encodage compact d'un verdict — deux analyses au même verdict et au
    /// même statut « en amélioration » partagent la même signature.
    private static func signature(pour analyse: AnalyseBasaleDetail) -> String {
        let code: String
        switch analyse.verdict {
        case .adaptee:               code = "adaptee"
        case .tropHaute:             code = "tropHaute"
        case .tropBasse:             code = "tropBasse"
        case .donneesInsuffisantes:  code = "insuffisant"
        }
        return "\(code)|\(analyse.enAmelioration)"
    }

    private var signatureVerdict: String { Self.signature(pour: analyse) }

    /// Observation « tendance basale » pour la pile d'insights de l'accueil —
    /// `nil` seulement faute de verdict (données insuffisantes). **Ne dépend
    /// plus du « vu »** : ouvrir le détail de l'analyse faisait disparaître la
    /// carte de l'accueil, alors qu'on veut pouvoir la retrouver. Le « vu »
    /// ne pilote plus que la pastille de l'onglet Analyses. La carte part
    /// seulement par suppression volontaire, ou quand le verdict n'existe plus.
    ///
    /// L'`id` est **dérivé de la signature** (pas aléatoire) : un verdict
    /// identique retombe sur le même identifiant, donc une suppression par
    /// l'utilisateur reste valable tant que le verdict ne change pas, et
    /// l'insight réapparaît naturellement dès que la tendance évolue.
    var insightNouvelleTendance: Insight? {
        guard analyse.verdict != .donneesInsuffisantes else { return nil }

        // Même verdict que la carte de la page d'analyse, écrit à côté de son
        // icône : jamais un nombre
        // de nuits seul (« 6 nuits ↘ » se lisait « 6 nuits descendantes »),
        // jamais une interprétation de dose.
        let constat = ConstatVerdictBasale(analyse: analyse)
        // Pas de phrase dessous : la conclusion à côté de l'icône suffit,
        // l'explication vit sur la page d'analyse.
        let message = ""
        let categorie: CategorieInsight
        let icone: String
        if analyse.enAmelioration {
            categorie = .positif
            icone = "arrow.up.forward.circle.fill"
        } else {
            switch analyse.verdict {
            case .tropHaute:
                categorie = .attention
                icone = "arrow.down.right.circle.fill"
            case .tropBasse:
                categorie = .attention
                icone = "arrow.up.right.circle.fill"
            case .adaptee:
                categorie = .positif
                icone = "checkmark.circle.fill"
            case .donneesInsuffisantes:
                return nil
            }
        }
        let microVisuel = MicroVisuelType.iconeEtTexte(systemName: icone, texte: constat.verdict)

        return Insight(
            id: Self.idDeterministe(signatureVerdict),
            categorie: categorie,
            titre: "Tendance nocturne",
            message: message,
            microVisuel: microVisuel,
            lienAnalyse: "tendance-nocturne",
            destination: .basale
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

    nonisolated private static func chargerEntrees(contexte: ModelContext) -> EntreesBasale {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique()
        // CGM / repas / sport / pauses : couvrent les 14 nuits (+ marge zone 1).
        let borneCourte = cal.date(byAdding: .day, value: -15, to: debutCourant) ?? debutCourant
        // Lentes : fenêtre large pour détecter le palier de dose courant et son début.
        let borneDose = cal.date(byAdding: .day, value: -120, to: debutCourant) ?? debutCourant

        let cgm = fetchCGM(contexte, depuis: borneCourte)
        let (lentes, rapides) = fetchInjections(contexte, depuis: borneDose)
        // Repas et resucrages sont deux faits distincts : les repas badgés
        // resucrage basculent côté `resucrages`, jamais comptés deux fois.
        let repas = ChargeurFaitsCoucher.repas(contexte, depuis: borneCourte)
        let resucrages = ChargeurFaitsCoucher.resucrages(contexte, depuis: borneCourte)
        let sports = fetchSports(contexte, depuis: borneCourte)
        let pauses = fetchPauses(contexte, depuis: borneCourte)

        return EntreesBasale(
            lectures: cgm, lentes: lentes, rapides: rapides,
            repas: repas, resucrages: resucrages, sports: sports, pauses: pauses
        )
    }

    nonisolated private static func fetchCGM(_ contexte: ModelContext, depuis: Date) -> [(date: Date, valeur: Int)] {
        var d = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= depuis },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        d.propertiesToFetch = [\.date, \.valeur]
        return ((try? contexte.fetch(d)) ?? []).map { (date: $0.date, valeur: $0.valeur) }
    }

    nonisolated private static func fetchInjections(
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

    nonisolated private static func fetchSports(_ contexte: ModelContext, depuis: Date) -> [(debut: Date, dureeMin: Int)] {
        let d = FetchDescriptor<ActiviteSportive>(predicate: #Predicate { $0.dateDebut >= depuis })
        return ((try? contexte.fetch(d)) ?? []).map { (debut: $0.dateDebut, dureeMin: $0.dureeMinutes) }
    }

    nonisolated private static func fetchPauses(_ contexte: ModelContext, depuis: Date) -> [(debut: Date, fin: Date?)] {
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
        EntreesBasale(lectures: [], lentes: [], rapides: [], repas: [],
                      resucrages: [], sports: [], pauses: [])
    }
}
