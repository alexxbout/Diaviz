//
//  JournalConteneurVue.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

/// Vue parent qui héberge les 3 sous-sections du Journal (Repas,
/// Médications, Activités sportives). Ne porte pas elle-même la
/// pillule switcher — celle-ci vit en `tabViewBottomAccessory` au
/// niveau racine (`AppTabVues`) et apparaît automatiquement en
/// Liquid Glass entre les pills de tab quand on est ici.
///
/// Cette vue se contente de :
/// - Rendre le bon enfant selon la section courante.
/// - Synchroniser `AppRouter.inJournalDetail` (pour piloter la
///   visibilité de l'accessoire) à l'apparition / disparition.
/// - Observer les changements de `AppRouter.journalSection` (poussés
///   par tap sur l'accessoire) pour swap le contenu sans push/pop.
struct JournalConteneurVue: View {

    @Environment(AppRouter.self) private var router

    /// Section courante. Initialisée par `init(initialSection:)`, puis
    /// maintenue en sync avec `router.journalSection` via `onChange`.
    @State private var section: SectionJournal

    init(initialSection: SectionJournal) {
        self._section = State(initialValue: initialSection)
    }

    var body: some View {
        Group {
            switch section {
            case .repas:
                // `ListeRepasParSection` lit ses repas depuis le `RepasService`
                // partagé via l'environnement — pas de données passées ici.
                ListeRepasParSection()
            case .medications:
                MedicationsVue()
            case .sport:
                SportVue()
            }
        }
        .onAppear {
            router.inJournalDetail = true
            router.journalSection = section
        }
        .onDisappear {
            router.inJournalDetail = false
        }
        .onChange(of: router.journalSection) { _, nouvelle in
            // L'utilisateur a tapé un segment de l'accessoire de
            // tab bar — on swap le contenu local en conséquence.
            guard nouvelle != section else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                section = nouvelle
            }
        }
    }
}

// MARK: - Aperçu

#Preview("Journal détail — Repas") {
    NavigationStack {
        JournalConteneurVue(initialSection: .repas)
    }
    .environment(AppRouter())
    .environment(RepasService.apercu())
    .environment(HealthKitImportService.mockVide())
}

#Preview("Journal détail — Médications") {
    NavigationStack {
        JournalConteneurVue(initialSection: .medications)
    }
    .environment(AppRouter())
    .environment(RepasService.apercu())
    .environment(HealthKitImportService.mockVide())
}

#Preview("Journal détail — Sport") {
    NavigationStack {
        JournalConteneurVue(initialSection: .sport)
    }
    .environment(AppRouter())
    .environment(RepasService.apercu())
    .environment(HealthKitImportService.mockVide())
}
