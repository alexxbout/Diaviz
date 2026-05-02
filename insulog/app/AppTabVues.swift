//
//  AppTabView.swift
//  insulog
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

    @State private var showingSearch = false

    /// Service d'import — pris depuis le singleton plutôt qu'instancié
    /// localement, parce qu'il porte de l'état partagé avec le badge
    /// de la `JournalVue` et le bouton d'import de la `SportVue`.
    @State private var importService = HealthKitImportService.shared

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
                JournalVue(nombreRepas: 0, sections: [])
            }
            .badge(importService.nombreEnAttente)

            Tab("Analyses", systemImage: "chart.dots.scatter") {
                AnalysesVue()
            }

            Tab("Recherche", systemImage: "magnifyingglass", role: TabRole.search) {
                RecercheVue()
            }
        }
        // Injection de la racine — toutes les vues filles consomment le
        // même service via `@Environment(HealthKitImportService.self)`,
        // ce qui rend les previews capable de fournir un mock isolé.
        .environment(importService)
        .onAppear { ouvrirSheetSiBesoin() }
        .sheet(isPresented: $afficherSheetImport) {
            SheetImportApplehealth(service: importService)
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

#Preview {
    AppTabVues()
}
