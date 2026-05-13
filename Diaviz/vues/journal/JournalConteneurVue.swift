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

    /// Données des repas — passées par `JournalVue` puisque
    /// `ListeRepasParSection` n'a pas son propre service.
    let sections: [(titre: String, repas: [Repas])]

    @Environment(AppRouter.self) private var router

    /// Section courante. Initialisée par `init(initialSection:…)`,
    /// puis maintenue en sync avec `router.journalSection` via
    /// `onChange`.
    @State private var section: SectionJournal

    init(initialSection: SectionJournal, sections: [(titre: String, repas: [Repas])]) {
        self.sections = sections
        self._section = State(initialValue: initialSection)
    }

    var body: some View {
        Group {
            switch section {
            case .repas:
                ListeRepasParSection(sections: sections)
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

private let _previewSectionsVides: [(titre: String, repas: [Repas])] = [
    (titre: "Petit déjeuner", repas: []),
    (titre: "Déjeuner", repas: []),
    (titre: "En-cas", repas: []),
    (titre: "Dîner", repas: []),
]

#Preview("Journal détail — Repas") {
    NavigationStack {
        JournalConteneurVue(initialSection: .repas, sections: _previewSectionsVides)
    }
    .environment(AppRouter())
    .environment(HealthKitImportService.mockVide())
}

#Preview("Journal détail — Médications") {
    NavigationStack {
        JournalConteneurVue(initialSection: .medications, sections: _previewSectionsVides)
    }
    .environment(AppRouter())
    .environment(HealthKitImportService.mockVide())
}

#Preview("Journal détail — Sport") {
    NavigationStack {
        JournalConteneurVue(initialSection: .sport, sections: _previewSectionsVides)
    }
    .environment(AppRouter())
    .environment(HealthKitImportService.mockVide())
}
