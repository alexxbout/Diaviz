//
//  AppTabView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Vue racine — `TabView` portant les quatre onglets de l'app.
///
/// Branchée sur `HealthKitImportService.shared` pour deux usages :
/// 1. **Badge** sur l'onglet Journal — reflète en temps réel le nombre
///    de workouts Apple Santé en attente d'import (parce que c'est
///    depuis le Journal qu'on accède à la page Sport, donc la source
///    cible des imports).
/// 2. **Ouverture automatique** de la sheet d'import au lancement si
///    des activités sont détectées, pour éviter qu'elles passent
///    inaperçues (et n'avoir pas à les chercher dans la page Sport).
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

    /// Pilote la sheet d'import. Mis à `true` automatiquement à
    /// l'apparition si `importService.aDesImportsEnAttente`, ou par
    /// l'utilisateur via les boutons d'accès dédiés.
    @State private var afficherSheetImport = false

    /// Drapeau anti-réouverture : `onAppear` peut être rejoué à chaque
    /// retour au foreground ou changement d'orientation. On ne veut
    /// l'ouverture automatique qu'au tout premier `onAppear` de la
    /// session.
    @State private var ouvertureAutoTentee = false

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
        .onAppear { ouvrirSheetSiBesoin() }
        .sheet(isPresented: $afficherSheetImport) {
            SheetImportAppleHealth(service: importService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Ouvre la sheet uniquement au premier appel d'`onAppear` qui
    /// trouve des imports en attente. SwiftUI peut renvoyer des
    /// `onAppear` répétés (changement d'orientation, fenêtre repassée
    /// au premier plan) — on ne veut pas re-pousser la sheet si
    /// l'utilisateur l'a déjà fermée.
    private func ouvrirSheetSiBesoin() {
        guard !ouvertureAutoTentee else { return }
        ouvertureAutoTentee = true
        if importService.aDesImportsEnAttente {
            afficherSheetImport = true
        }
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
