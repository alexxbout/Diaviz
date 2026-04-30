//
//  RepasDetailVue.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct RepasDetailVue: View {
    @State private var sections: [(titre: String, repas: [Repas])]

    /// Date sélectionnée par le `GraphRepasJournee` via swipe horizontal.
    /// Sert à filtrer les sections affichées en dessous.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private static let titresSections = ["Petit déjeuner", "Déjeuner", "En-cas", "Dîner"]

    init(sections: [(titre: String, repas: [Repas])]) {
        let initial = Self.titresSections.map { titre in
            (titre: titre, repas: sections.first(where: { $0.titre == titre })?.repas ?? [])
        }
        _sections = State(initialValue: initial)
    }

    /// Projection à plat des repas validés en `RepasGraph`, regroupés
    /// avec leur libellé de section. C'est le format consommé par le graphe.
    private var repasGraph: [RepasGraph] {
        sections.flatMap { section in
            section.repas
                .filter { !$0.aliments.isEmpty }
                .map { RepasGraph($0, label: section.titre) }
        }
    }

    var body: some View {
        List {
            // Graph en première section, sans en-tête. SwiftUI gère
            // automatiquement la hauteur de cette cellule comme pour
            // n'importe quelle autre row de la List.
            Section {
                GraphRepasJournee(repas: repasGraph, selectedDate: $selectedDate)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(sections.indices, id: \.self) { sectionIndex in
                Section(sections[sectionIndex].titre) {
                    contenuSection(sectionIndex: sectionIndex)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Repas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: AjouterRepasVue()) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func contenuSection(sectionIndex: Int) -> some View {
        let cal = Calendar.current
        let repasAvecAliments = sections[sectionIndex].repas
            .filter { !$0.aliments.isEmpty }
            .filter { cal.isDate($0.heure, inSameDayAs: selectedDate) }

        if repasAvecAliments.isEmpty {
            Text("Aucun repas enregistré")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
        } else {
            ForEach(repasAvecAliments) { unRepas in
                HStack {
                    Text(unRepas.heure, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(unRepas.totalGlucides) g de glucides")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }

                ForEach(unRepas.aliments) { aliment in
                    CarteAliment(
                        emoji: aliment.emoji,
                        nom: aliment.nom,
                        quantite: aliment.quantite,
                        glucides: aliment.glucides,
                        insuline: aliment.insuline
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            supprimerAliment(aliment.id, dansSectionIndex: sectionIndex)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func supprimerAliment(_ alimentId: UUID, dansSectionIndex sectionIndex: Int) {
        for repasIndex in sections[sectionIndex].repas.indices {
            sections[sectionIndex].repas[repasIndex].aliments.removeAll { $0.id == alimentId }
        }
        sections[sectionIndex].repas.removeAll { $0.aliments.isEmpty }
    }
}
