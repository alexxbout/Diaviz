//
//  ListeRepasParSection.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct ListeRepasParSection: View {

    /// Service hub partagé via l'environnement. Source de vérité live : un repas
    /// ajouté (ou supprimé) ailleurs se reflète ici sans redémarrage.
    @Environment(RepasService.self) private var repasService

    /// Date sélectionnée par le `GrapheJourneeRepas` via swipe horizontal.
    /// Sert à filtrer les sections affichées en dessous.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Sections du jour sélectionné, recalculées depuis le hub à chaque render
    /// (les 4 tranches canoniques, vides comprises). Plus de copie `@State`
    /// figée : la liste suit le service observable.
    private var sections: [(titre: String, repas: [Repas])] {
        repasService.sectionsDuJour(selectedDate)
    }

    /// Projection à plat des repas non vides en `RepasGraph`, avec leur libellé
    /// de section. Format consommé par le graphe.
    private var repasGraph: [RepasGraph] {
        sections.flatMap { section in
            section.repas
                .filter { !$0.aliments.isEmpty }
                .map { RepasGraph($0, label: section.titre) }
        }
    }

    var body: some View {
        List {
            // Graph en première section, sans en-tête.
            Section {
                GrapheJourneeRepas(repas: repasGraph, selectedDate: $selectedDate)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(sections, id: \.titre) { section in
                Section(section.titre) {
                    contenuSection(section)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Repas")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: AjouterRepasVue()) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func contenuSection(_ section: (titre: String, repas: [Repas])) -> some View {
        let repasAvecAliments = section.repas.filter { !$0.aliments.isEmpty }

        if repasAvecAliments.isEmpty {
            Text("Aucun repas enregistré")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
        } else {
            ForEach(repasAvecAliments) { unRepas in
                // En-tête du repas : emoji + infos + mini-courbe glycémique.
                // Tap → détail. Pas de swipe ici : on ne supprime pas un repas
                // entier d'un geste depuis sa ligne d'en-tête.
                LigneRepas(repas: unRepas, titreSection: section.titre)

                // Détail des aliments — swipe sur un aliment le retire du hub
                // (et retire le repas s'il devient vide).
                ForEach(unRepas.aliments) { aliment in
                    CarteAliment(
                        emoji: aliment.emoji,
                        nom: aliment.nom,
                        quantite: aliment.quantite,
                        glucides: aliment.glucides,
                        insuline: aliment.insuline,
                        imageURL: aliment.imageURL
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            repasService.supprimerAliment(aliment, de: unRepas)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Aperçu

#Preview("Avec repas") {
    NavigationStack {
        ListeRepasParSection()
    }
    .environment(RepasService.apercu())
}

#Preview("Journée vide") {
    NavigationStack {
        ListeRepasParSection()
    }
    .environment(RepasService())
}
