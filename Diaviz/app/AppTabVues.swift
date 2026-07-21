//
//  AppTabView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftData
import SwiftUI

/// Vue racine — `TabView` portant les quatre onglets de l'app.
///
/// Branchée sur `HealthKitImportService.shared` pour afficher un
/// **badge** sur l'onglet Journal reflétant en temps réel le nombre de
/// workouts Apple Santé en attente d'import. L'import lui-même se fait
/// depuis la page Sport (sheet déclenchée par bouton dédié) — pas
/// d'ouverture automatique au lancement.
///
/// Présente automatiquement la sheet `SheetScoreMatin` au lancement de
/// l'app — résumé visuel mis en avant du score de la veille.
struct AppTabVues: View {

    @State private var showingSearch = false

    /// Onglet actif — sert uniquement à déclencher le retour haptique au
    /// changement d'onglet (`.sensoryFeedback` a besoin d'une valeur
    /// observable à surveiller). Aucun contrôle programmatique de la
    /// navigation n'en dépend.
    @State private var ongletActif: String = "accueil"

    /// Service hub des repas — source de vérité de l'onglet Journal. Démarré
    /// au boot via `.task` (contexte du hub), il fournit les sections du jour
    /// et le compteur de repas. En prod le hub est vide au départ → état vide
    /// honnête ; les previews injectent un container peuplé via
    /// `.modelContainer(RepasService.conteneurApercu)`.
    @State private var repasService = RepasService()

    /// Service d'import — pris depuis le singleton plutôt qu'instancié
    /// localement, parce qu'il porte de l'état partagé avec le badge
    /// de la `JournalVue` et le bouton d'import de la `SportVue`.
    @State private var importService = HealthKitImportService.shared

    /// Service de profil — partagé entre l'accueil (avatar) et la
    /// sheet `ProfilVue`. Injecté via `.environment` ; les vues le
    /// récupèrent par `@Environment(ProfilService.self)`.
    @State private var profilService = ProfilService.shared

    /// Service HealthKit — autorisation, synchro incrémentale et surveillance
    /// background des glycémies vers le hub.
    @State private var healthKit = HealthKitCGMService()

    /// Service du score — alimente la sheet du matin avec le vrai score de la
    /// veille (calculé depuis le hub).
    @State private var scoreService = ScoreService()

    /// Service de l'analyse basale (B1) — instance **unique** partagée entre
    /// l'onglet Analyses (détail), l'accueil (insight « nouvelle tendance »)
    /// et le badge de cet onglet. Doit être la même instance partout (pas un
    /// `@State` privé par vue) pour que « marquer comme vu » depuis le détail
    /// efface le badge vu par les deux autres écrans.
    @State private var analyseBasaleService = AnalyseBasaleService()

    /// Services des analyses B2/B3 — dépendent de `analyseBasaleService` pour
    /// l'ancrage de nuit (lente, glycémie au coucher). Mêmes règles d'instance
    /// unique partagée que B1.
    @State private var analyseEndormissementService = AnalyseEndormissementService()
    @State private var analyseCorrectionsService = AnalyseCorrectionsService()

    /// Contexte SwiftData du hub (pour récupérer le `ModelContainer`).
    @Environment(\.modelContext) private var modelContext

    /// Pilote la sheet « Score du matin ». Forcé à `true` à
    /// l'initialisation → auto-open à chaque lancement de l'app
    /// (l'utilisateur peut la dismisser ; elle reviendra au prochain
    /// cold start). Les previews héritent automatiquement de ce
    /// comportement, pas besoin de hack supplémentaire.
    @State private var afficherScoreMatin = false

    /// Jour pour lequel on souhaite pousser `DetailScoreVue` dans
    /// l'onglet Accueil. Écrit par le bouton « Voir les détails » de
    /// `SheetScoreMatin` ; observé par `AccueilVue` via binding qui
    /// déclenche la push via `navigationDestination(item:)`.
    @State private var jourDetailScore: Date?

    var body: some View {
        TabView(selection: $ongletActif) {
            Tab("Accueil", systemImage: "house", value: "accueil") {
                AccueilVue(jourDetailScore: $jourDetailScore)
            }

            Tab("Journal", systemImage: "long.text.page.and.pencil", value: "journal") {
                JournalVue()
            }
            .badge(importService.nombreEnAttente)

            Tab("Analyses", systemImage: "chart.dots.scatter", value: "analyses") {
                AnalysesVue()
            }
            .badge(analyseBasaleService.estNouvelleTendance ? "•" : "")

            Tab("Recherche", systemImage: "bubble.left.and.text.bubble.right", value: "recherche", role: TabRole.search) {
                RecercheVue()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Léger retour haptique au changement d'onglet — cohérent avec les
        // autres `.sensoryFeedback` déjà présents (site d'injection, timeline
        // basale, bouton valider repas).
        .sensoryFeedback(.selection, trigger: ongletActif)
        // Injection de la racine — toutes les vues filles consomment le
        // même service via `@Environment(HealthKitImportService.self)`,
        // ce qui rend les previews capable de fournir un mock isolé.
        .environment(importService)
        .environment(profilService)
        .environment(repasService)
        .environment(analyseBasaleService)
        .environment(analyseEndormissementService)
        .environment(analyseCorrectionsService)
        .task {
            repasService.demarrer(contexte: modelContext)
            scoreService.demarrer(contexte: modelContext)
            // B1 doit être démarré (et son `analyse` à jour) avant B2/B3, qui
            // lisent `analyseBasaleService.analyse` — d'où l'attente séquentielle.
            await analyseBasaleService.demarrer(contexte: modelContext)
            async let endo: Void = analyseEndormissementService.demarrer(contexte: modelContext, basale: analyseBasaleService)
            async let corr: Void = analyseCorrectionsService.demarrer(contexte: modelContext, basale: analyseBasaleService)
            _ = await (endo, corr)
            // Sheet du matin : seulement après 6h, une fois par jour, et s'il
            // existe un score de la veille consolidé.
            if doitAfficherSheetMatin() {
                afficherScoreMatin = true
                UserDefaults.standard.set(
                    Calendar.current.startOfDay(for: Date()),
                    forKey: Self.cleSheetMatin
                )
            }
            await healthKit.demanderAcces()
            await healthKit.synchroniser(container: modelContext.container)
            healthKit.demarrerSurveillance(container: modelContext.container)
            await importService.demanderAcces()
            await importService.rafraichir()
            // Le CGM vient d'être synchronisé : recalcule les réponses
            // glycémiques des repas (au démarrage elles étaient toutes en
            // attente, faute de glycémies encore chargées).
            repasService.rafraichirAnalyses()
        }
        .sheet(isPresented: $afficherScoreMatin) {
            SheetScoreMatin(
                faits: faitsScoreMatin,
                date: jourScoreMatin,
                onAfficherDetails: {
                    // L'utilisateur a tapé « Voir les détails » : la
                    // sheet vient de `dismiss()` côté enfant, on
                    // enchaîne sur la push de `DetailScoreVue` dans
                    // l'onglet Accueil via le binding.
                    jourDetailScore = jourScoreMatin
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Clé UserDefaults : dernier jour calendaire où la sheet du matin a été
    /// affichée (pour la limiter à une fois par jour).
    private static let cleSheetMatin = "sheetMatin.dernierJourAffiche"

    /// Faut-il ouvrir la sheet du score du matin à ce lancement ?
    /// Trois conditions : il est ≥ 6h (la veille métabolique est consolidée),
    /// elle n'a pas déjà été montrée aujourd'hui, et un score de la veille existe.
    private func doitAfficherSheetMatin() -> Bool {
        let cal = Calendar.current
        let now = Date()
        guard cal.component(.hour, from: now) >= 6 else { return false }
        guard scoreService.joursNavigables.last != nil else { return false }
        let aujourdhui = cal.startOfDay(for: now)
        if let dernier = UserDefaults.standard.object(forKey: Self.cleSheetMatin) as? Date,
           cal.isDate(dernier, inSameDayAs: aujourdhui) {
            return false
        }
        return true
    }

    /// Date d'hier — utilisée comme date affichée par la sheet score du
    /// matin (le score résume toujours la journée précédente).
    private var hier: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    /// Jour montré par la sheet du matin = dernier jour métabolique **consolidé**
    /// (terminé). En usage normal c'est la veille ; en pleine nuit c'est
    /// l'avant-veille (la veille est encore en cours, pas de score figé).
    private var jourScoreMatin: Date {
        scoreService.joursNavigables.last ?? hier
    }

    /// `FaitsJour` réel du dernier jour consolidé pour la sheet du matin.
    /// Repli neutre seulement si le hub est vide (sheet alors non affichée).
    private var faitsScoreMatin: FaitsJour {
        scoreService.score(pour: jourScoreMatin)?.faits ?? Self.faitsIndisponibles
    }

    /// Repli quand aucun score de la veille n'est disponible.
    private static let faitsIndisponibles = FaitsJour(
        score: 0, tir: 0, tbrLevel1: 0, tbrLevel2: 0, tarLevel1: 0, tarLevel2: 0,
        hypoCount: 0, severeHypoCount: 0, peakTime: nil, peakValue: nil,
        mealContext: nil, sportContext: nil
    )
}

#Preview {
    AppTabVues()
        .modelContainer(RepasService.conteneurApercu)
}
