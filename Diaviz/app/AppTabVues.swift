//
//  AppTabView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

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

    /// Sections de repas affichées dans l'onglet Journal. Vide par
    /// défaut tant qu'aucun service de repas n'est branché ; les
    /// previews injectent des exemples pour exercer le rendu.
    let nombreRepas: Int
    let sectionsJournal: [(titre: String, repas: [Repas])]

    init(
        nombreRepas: Int = 0,
        sectionsJournal: [(titre: String, repas: [Repas])] = []
    ) {
        self.nombreRepas = nombreRepas
        self.sectionsJournal = sectionsJournal
    }

    @State private var showingSearch = false

    /// Service d'import — pris depuis le singleton plutôt qu'instancié
    /// localement, parce qu'il porte de l'état partagé avec le badge
    /// de la `JournalVue` et le bouton d'import de la `SportVue`.
    @State private var importService = HealthKitImportService.shared

    /// Service de profil — partagé entre l'accueil (avatar) et la
    /// sheet `ProfilVue`. Injecté via `.environment` ; les vues le
    /// récupèrent par `@Environment(ProfilService.self)`.
    @State private var profilService = ProfilService.shared

    /// Pilote la sheet « Score du matin ». Forcé à `true` à
    /// l'initialisation → auto-open à chaque lancement de l'app
    /// (l'utilisateur peut la dismisser ; elle reviendra au prochain
    /// cold start). Les previews héritent automatiquement de ce
    /// comportement, pas besoin de hack supplémentaire.
    @State private var afficherScoreMatin = true

    var body: some View {
        TabView {
            Tab("Accueil", systemImage: "house") {
                AccueilVue()
            }

            Tab("Journal", systemImage: "long.text.page.and.pencil") {
                JournalVue(nombreRepas: nombreRepas, sections: sectionsJournal)
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
        .sheet(isPresented: $afficherScoreMatin) {
            SheetScoreMatin(faits: faitsScoreMatin, date: hier)
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

private func _previewDate(hour: Int, minute: Int, daysAgo: Int = 0) -> Date {
    let cal = Calendar.current
    let jour = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return cal.date(bySettingHour: hour, minute: minute, second: 0, of: jour) ?? Date()
}

private let _previewSections: [(titre: String, repas: [Repas])] = [
    (titre: "Petit déjeuner", repas: [
        Repas(
            heure: _previewDate(hour: 7, minute: 30),
            aliments: [
                Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
                Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
                Aliment(emoji: "🥛", nom: "Lait demi-écrémé", quantite: 200, glucides: 10, insuline: 0.5),
            ],
            etatAnalyse: nil,
            iobAuDebut: nil
        )
    ]),
    (titre: "Déjeuner", repas: [
        Repas(
            heure: _previewDate(hour: 12, minute: 30),
            aliments: [
                Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
                Aliment(emoji: "🍗", nom: "Poulet grillé", quantite: 150, glucides: 0, insuline: 0.0),
                Aliment(emoji: "🥦", nom: "Brocolis vapeur", quantite: 200, glucides: 8, insuline: 0.0),
            ],
            etatAnalyse: nil,
            iobAuDebut: 0.6
        )
    ]),
    (titre: "En-cas", repas: [
        Repas(
            heure: _previewDate(hour: 16, minute: 0),
            aliments: [
                Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0.0),
            ],
            etatAnalyse: nil,
            iobAuDebut: 2.2
        )
    ]),
    (titre: "Dîner", repas: [
        Repas(
            heure: _previewDate(hour: 19, minute: 45),
            aliments: [
                Aliment(emoji: "🍚", nom: "Riz basmati", quantite: 70, glucides: 56, insuline: 3.0),
                Aliment(emoji: "🐟", nom: "Saumon grillé", quantite: 130, glucides: 0, insuline: 0.0),
                Aliment(emoji: "🥗", nom: "Salade verte", quantite: 80, glucides: 2, insuline: 0.0),
            ],
            etatAnalyse: nil,
            iobAuDebut: 0.4
        )
    ]),
]

private var _previewNombreRepas: Int {
    _previewSections.reduce(0) { $0 + $1.repas.count }
}

#Preview {
    AppTabVues(
        nombreRepas: _previewNombreRepas,
        sectionsJournal: _previewSections
    )
}
