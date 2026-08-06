//
//  ListeResucrages.swift
//  diaviz
//

import SwiftUI
import SwiftData

/// Page racine « Resucrage ». Pushée depuis `JournalVue` via un
/// `NavigationLink`, donc pas de `NavigationStack` propre — hérite de la
/// stack du parent. Même structure que `MedicationsVue`.
///
/// V1 : liste à plat groupée par jour, création + suppression seulement
/// (pas d'édition — corriger un resucrage = le supprimer et le refaire).
struct ListeResucrages: View {

    @Environment(\.modelContext) private var modelContext
    @State private var service = ResucragesService()
    @State private var afficherNouveauResucrage = false

    var body: some View {
        List {
            if service.resucrages.isEmpty {
                ContentUnavailableView(
                    "Aucun resucrage",
                    systemImage: "cross.case",
                    description: Text("Vos resucrages apparaîtront ici")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(joursTries, id: \.self) { jour in
                    Section(libelleJour(jour)) {
                        ForEach(service.resucragesDuJour(jour)) { resucrage in
                            LigneResucrage(resucrage: resucrage)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        service.supprimer(resucrage.id)
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Resucrage")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    afficherNouveauResucrage = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                }
                .accessibilityLabel("Ajouter un resucrage")
            }
        }
        .sheet(isPresented: $afficherNouveauResucrage) {
            SheetNouveauResucrage { resucrage in
                service.enregistrer(resucrage)
            }
        }
        .task { service.demarrer(contexte: modelContext) }
    }

    /// Jours distincts présents dans `service.resucrages`, du plus récent
    /// au plus ancien — même dérivation que le regroupement par nuit de B1.
    private var joursTries: [Date] {
        let cal = Calendar.current
        let jours = Set(service.resucrages.map { cal.startOfDay(for: $0.date) })
        return jours.sorted(by: >)
    }

    private func libelleJour(_ jour: Date) -> String {
        if Calendar.current.isDateInToday(jour) { return "Aujourd'hui" }
        if Calendar.current.isDateInYesterday(jour) { return "Hier" }
        return Self.formatterJour.string(from: jour).capitalizedFirstLetter
    }

    private static let formatterJour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()
}

private extension String {
    var capitalizedFirstLetter: String {
        guard let premiere = first else { return self }
        return String(premiere).uppercased() + dropFirst()
    }
}

// MARK: - Aperçu

#Preview {
    NavigationStack {
        ListeResucrages()
    }
    .modelContainer(ResucragesService.conteneurApercu)
}
