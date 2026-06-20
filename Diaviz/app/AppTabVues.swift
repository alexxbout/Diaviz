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

    /// Contexte SwiftData du hub (pour récupérer le `ModelContainer`).
    @Environment(\.modelContext) private var modelContext

    /// Pilote la sheet « Score du matin ». Forcé à `true` à
    /// l'initialisation → auto-open à chaque lancement de l'app
    /// (l'utilisateur peut la dismisser ; elle reviendra au prochain
    /// cold start). Les previews héritent automatiquement de ce
    /// comportement, pas besoin de hack supplémentaire.
    @State private var afficherScoreMatin = true

    /// Jour pour lequel on souhaite pousser `DetailScoreVue` dans
    /// l'onglet Accueil. Écrit par le bouton « Voir les détails » de
    /// `SheetScoreMatin` ; observé par `AccueilVue` via binding qui
    /// déclenche la push via `navigationDestination(item:)`.
    @State private var jourDetailScore: Date?

    var body: some View {
        TabView {
            Tab("Accueil", systemImage: "house") {
                AccueilVue(jourDetailScore: $jourDetailScore)
            }

            Tab("Journal", systemImage: "long.text.page.and.pencil") {
                JournalVue(
                    nombreRepas: repasService.nombreRepasAujourdhui,
                    sections: repasService.sectionsAujourdhui
                )
            }
            .badge(importService.nombreEnAttente)

            Tab("Analyses", systemImage: "chart.dots.scatter") {
                AnalysesVue()
            }

            Tab("Recherche", systemImage: "bubble.left.and.text.bubble.right", role: TabRole.search) {
                RecercheVue()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Injection de la racine — toutes les vues filles consomment le
        // même service via `@Environment(HealthKitImportService.self)`,
        // ce qui rend les previews capable de fournir un mock isolé.
        .environment(importService)
        .environment(profilService)
        .task {
            repasService.demarrer(contexte: modelContext)
            await healthKit.demanderAcces()
            await healthKit.synchroniser(container: modelContext.container)
            healthKit.demarrerSurveillance(container: modelContext.container)
        }
        .sheet(isPresented: $afficherScoreMatin) {
            SheetScoreMatin(
                faits: faitsScoreMatin,
                date: hier,
                onAfficherDetails: {
                    // L'utilisateur a tapé « Voir les détails » : la
                    // sheet vient de `dismiss()` côté enfant, on
                    // enchaîne sur la push de `DetailScoreVue` dans
                    // l'onglet Accueil via le binding.
                    jourDetailScore = hier
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Date d'hier — utilisée comme date affichée par la sheet score du
    /// matin (le score résume toujours la journée précédente).
    private var hier: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    /// Mock de `FaitsJour` pour la sheet score du matin — score 82 pour
    /// rester aligné visuellement avec la carte score affichée sur
    /// l'accueil. Sera remplacé par les vraies métriques quand la
    /// couche d'analyses sera branchée.
    private var faitsScoreMatin: FaitsJour {
        FaitsJour(
            score: 82,
            tir: 79,
            tbrLevel1: 1,
            tbrLevel2: 0,
            tarLevel1: 17,
            tarLevel2: 3,
            hypoCount: 1,
            severeHypoCount: 0,
            peakTime: "13:30",
            peakValue: 232,
            mealContext: nil,
            sportContext: nil
        )
    }
}

#Preview {
    AppTabVues()
        .modelContainer(RepasService.conteneurApercu)
}
