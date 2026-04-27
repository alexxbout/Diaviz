//
//  RepasView.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct JournalVue: View {
    let nombreRepas: Int
    let sections: [(titre: String, repas: [Repas])]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink(destination: RepasDetailVue(sections: sections)) {
                    CarteSection(
                        icone: "fork.knife",
                        titre: "Repas",
                        sousTitre: "\(nombreRepas) repas enregistré\(nombreRepas > 1 ? "s" : "") aujourd'hui",
                        couleur: .blue
                    )
                }

                CarteSection(
                    icone: "figure.run",
                    titre: "Activités sportives",
                    sousTitre: "Aucune activité aujourd'hui",
                    couleur: .orange
                )

                CarteSection(
                    icone: "syringe",
                    titre: "Médications",
                    sousTitre: "Aucune médication aujourd'hui",
                    couleur: .purple
                )

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Journal")
        }
    }
}

// MARK: - Données de preview

private func makeDate(hour: Int, minute: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
}

private let previewRepas: [(titre: String, repas: [Repas])] = [
    (
        titre: "Petit déjeuner",
        repas: [
            Repas(heure: makeDate(hour: 7, minute: 30), aliments: [
                Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
                Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
                Aliment(emoji: "🥛", nom: "Lait demi-écrémé", quantite: 200, glucides: 10, insuline: 0.5),
            ]),
            Repas(heure: makeDate(hour: 9, minute: 0), aliments: [
                Aliment(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 19, insuline: 1.0),
            ]),
        ]
    ),
    (
        titre: "Déjeuner",
        repas: [
            Repas(heure: makeDate(hour: 12, minute: 30), aliments: [
                Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
                Aliment(emoji: "🍗", nom: "Poulet grillé", quantite: 150, glucides: 0, insuline: 0.0),
                Aliment(emoji: "🥦", nom: "Brocolis vapeur", quantite: 200, glucides: 8, insuline: 0.0),
            ]),
        ]
    ),
    (
        titre: "Dîner",
        repas: [
            Repas(heure: makeDate(hour: 19, minute: 45), aliments: [
                Aliment(emoji: "🍚", nom: "Riz basmati", quantite: 70, glucides: 56, insuline: 3.0),
                Aliment(emoji: "🐟", nom: "Saumon grillé", quantite: 130, glucides: 0, insuline: 0.0),
                Aliment(emoji: "🥗", nom: "Salade verte", quantite: 80, glucides: 2, insuline: 0.0),
            ]),
        ]
    ),
]

#Preview("Journal") {
    JournalVue(nombreRepas: previewRepas.count, sections: previewRepas)
}
#Preview("Détail repas") {
    NavigationStack {
        RepasDetailVue(sections: previewRepas)
    }
}

