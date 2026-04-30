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
        let titreSection = sections[sectionIndex].titre
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
                // En-tête du repas : emoji + infos + mini-courbe glycémique.
                // Tap → sheet de détail. Swipe → suppression du repas entier.
                LigneRepasJournal(repas: unRepas, titreSection: titreSection)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            supprimerRepas(unRepas.id, dansSectionIndex: sectionIndex)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }

                // Détail des aliments du repas. Le swipe sur un aliment
                // permet de le retirer sans supprimer le repas entier.
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

    /// Supprime un repas entier de la section (swipe sur la row d'en-tête).
    private func supprimerRepas(_ repasId: UUID, dansSectionIndex sectionIndex: Int) {
        sections[sectionIndex].repas.removeAll { $0.id == repasId }
    }

    /// Supprime un aliment isolé d'un repas (swipe sur sa CarteAliment).
    /// Si le repas se retrouve vide, on le retire aussi pour cohérence.
    private func supprimerAliment(_ alimentId: UUID, dansSectionIndex sectionIndex: Int) {
        for repasIndex in sections[sectionIndex].repas.indices {
            sections[sectionIndex].repas[repasIndex].aliments.removeAll { $0.id == alimentId }
        }
        sections[sectionIndex].repas.removeAll { $0.aliments.isEmpty }
    }
}

// MARK: - Aperçu

private func _previewDate(_ h: Int, _ m: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
}

// Couvre les 6 cas du `MiniCourbeReponse` pour valider chaque rendu :
// - Petit déjeuner → bon (verdict vert)
// - Déjeuner → moyen (verdict orange) + mauvais (verdict rouge)
// - En-cas → sans injection (tiret) + en attente (icône horloge)
// - Dîner → données manquantes (icône warning)
private let _previewSections: [(titre: String, repas: [Repas])] = [
    (titre: "Petit déjeuner", repas: [
        Repas(
            heure: _previewDate(7, 30),
            aliments: [
                Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
                Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.bon)
        ),
    ]),
    (titre: "Déjeuner", repas: [
        Repas(
            heure: _previewDate(12, 30),
            aliments: [
                Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
                Aliment(emoji: "🥦", nom: "Brocolis vapeur", quantite: 200, glucides: 8, insuline: 0.5),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.moyen)
        ),
        Repas(
            heure: _previewDate(13, 30),
            aliments: [
                Aliment(emoji: "🍕", nom: "Pizza margherita", quantite: 300, glucides: 90, insuline: 5.0),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.mauvais)
        ),
    ]),
    (titre: "En-cas", repas: [
        Repas(
            heure: _previewDate(16, 0),
            aliments: [
                Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0.0),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.sansInjection)
        ),
        Repas(
            heure: _previewDate(17, 30),
            aliments: [
                Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 1.0),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.enAttente)
        ),
    ]),
    (titre: "Dîner", repas: [
        Repas(
            heure: _previewDate(19, 45),
            aliments: [
                Aliment(emoji: "🍚", nom: "Riz basmati", quantite: 70, glucides: 56, insuline: 3.0),
                Aliment(emoji: "🐟", nom: "Saumon grillé", quantite: 130, glucides: 0, insuline: 0.0),
            ],
            etatAnalyse: ReponseGlycemiqueServiceMock.cas(.donneesManquantes)
        ),
    ]),
]

#Preview("Avec repas") {
    NavigationStack {
        RepasDetailVue(sections: _previewSections)
    }
}

#Preview("Journée vide") {
    NavigationStack {
        RepasDetailVue(sections: [])
    }
}
