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

    /// Service du mining R1 (ratio observé) — cache mémoire recalculé sur
    /// mutation du hub, pas à chaque frappe de saisie. Lit `repasService.repas`
    /// directement, aucun fetch SwiftData séparé.
    @State private var analyseRatioService = AnalyseRatioService()

    /// Contexte SwiftData du hub (pour récupérer le `ModelContainer`).
    @Environment(\.modelContext) private var modelContext

    /// Jour pour lequel on souhaite pousser `DetailScoreVue` dans l'onglet
    /// Accueil — écrit au tap sur la carte score, observé par `AccueilVue`
    /// via binding qui déclenche la push via `navigationDestination(item:)`.
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

            Tab("Analyses", systemImage: "chart.bar.fill", value: "analyses") {
                AnalysesVue()
            }
            // `nil`, pas `""` : une chaîne vide non-nil affichait quand même
            // une pastille (vide) en permanence, quel que soit
            // `estNouvelleTendance`.
            .badge(analyseBasaleService.estNouvelleTendance ? Text("•") : nil)

            Tab("Recherche", systemImage: "sparkle.magnifyingglass", value: "recherche", role: TabRole.search) {
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
        .environment(analyseRatioService)
        .task {
            repasService.demarrer(contexte: modelContext)
            analyseRatioService.recalculer(depuis: repasService.repas)
            // B1 doit être démarré (et son `analyse` à jour) avant B2/B3, qui
            // lisent `analyseBasaleService.analyse` — d'où l'attente séquentielle.
            await analyseBasaleService.demarrer(contexte: modelContext)
            async let endo: Void = analyseEndormissementService.demarrer(contexte: modelContext, basale: analyseBasaleService)
            async let corr: Void = analyseCorrectionsService.demarrer(contexte: modelContext, basale: analyseBasaleService)
            _ = await (endo, corr)
            await healthKit.demanderAcces()
            await healthKit.synchroniser(container: modelContext.container)
            healthKit.demarrerSurveillance(container: modelContext.container)
            await importService.demanderAcces()
            await importService.rafraichir()
            // Le CGM vient d'être synchronisé : recalcule les réponses
            // glycémiques des repas (au démarrage elles étaient toutes en
            // attente, faute de glycémies encore chargées).
            repasService.rafraichirAnalyses()
            // Les verdicts persistés viennent de changer (repas passés de
            // enAttente à disponible) : remine le ratio observé.
            analyseRatioService.recalculer(depuis: repasService.repas)
        }
    }

}

#if DEBUG
extension AppTabVues {

    /// Container in-memory portant l'intégralité du schéma du hub (mêmes
    /// types que `DiavizApp.modelContainer`), peuplé en réutilisant les jeux
    /// d'exemple déjà maintenus par chaque service pour ses propres previews,
    /// plus l'historique dédié `RepasService.echantillonsApercuR1()` (hors
    /// fenêtre CGM, verdicts posés directement) qui fait franchir le seuil de
    /// R1 sur deux moments et illustre écart détecté / bien calibré /
    /// progression partielle. `EtatDeclare`/`Medicament`/`PeriodePause`
    /// restent vides, aucune saisie n'existe encore pour ces types. Pas de
    /// données ciblées pour B1 (tendance basale) ici — se vérifie mieux avec
    /// un jeu dédié sur le composant concerné, pas dans ce préréglage général.
    @MainActor
    static var conteneurApercuComplet: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: GlucoseReading.self, Injection.self, Repas.self, Aliment.self,
                 ActiviteSportive.self, EtatDeclare.self, Medicament.self, PeriodePause.self,
                 Resucrage.self,
            configurations: config
        )
        let contexte = container.mainContext
        for lecture in ScoreService.echantillonsApercu() { contexte.insert(lecture) }
        for repas in RepasService.echantillonsApercu() + RepasService.echantillonsApercuR1() { contexte.insert(repas) }
        for injection in InjectionsService.echantillonsApercu() { contexte.insert(injection) }
        for activite in ActivitesSportService.echantillonsApercu() { contexte.insert(activite) }
        try? contexte.save()
        return container
    }
}

#Preview("App complète") {
    // `ProfilService.shared` dans le process de preview est isolé du vrai
    // profil de l'iPhone (`UserDefaults` séparé de l'appareil réel) — sans
    // ça les cartes de ratio, seuils, etc. resteraient vides ici.
    ProfilService.shared.mettreAJour {
        $0 = ProfilUtilisateur(
            prenom: "Camille",
            poidsKg: 78,
            insulineRapide: .fiasp,
            insulineLente: .tresiba,
            dureeActionInsulineHeures: 3.5,
            modeRatio: .parMoment,
            ratioUnique: nil,
            ratiosParMoment: RatiosParMoment(
                petitDejeuner: 8,
                dejeuner: 12,
                gouter: 15,
                diner: 10
            ),
            ratioCorrection: 35,
            horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(),
            preferencesAvancees: PreferencesAvancees()
        )
    }
    return AppTabVues()
        .modelContainer(AppTabVues.conteneurApercuComplet)
}
#endif
