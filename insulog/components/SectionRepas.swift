//
//  SectionRepas.swift
//  insulog
//
//  Created by Alexandre on 22/04/2026.
//

import SwiftUI

struct SectionRepas: View {
    let titre: String
    let repas: [Repas]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(titre)
                    .fontWeight(.bold)
                    .foregroundStyle(.black)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            if repas.isEmpty || repas.allSatisfy({ $0.aliments.isEmpty }) {
                Text("Aucun repas enregistré")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(repas.enumerated()), id: \.element.id) { index, unRepas in
                    VStack(spacing: 8) {
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
                            .padding(.vertical, 2)
                        }
                    }

                    if index < repas.count - 1 {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding([.horizontal, .bottom])
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    VStack {
        SectionRepas(
            titre: "Déjeuner",
            repas: [
                Repas(
                    heure: Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: Date())!,
                    aliments: [
                        Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
                        Aliment(emoji: "🍗", nom: "Poulet grillé", quantite: 150, glucides: 0, insuline: 0.0),
                    ]
                ),
                Repas(
                    heure: Calendar.current.date(bySettingHour: 13, minute: 15, second: 0, of: Date())!,
                    aliments: [
                        Aliment(emoji: "🧀", nom: "Fromage blanc 0% de matière grasse aux herbes de Provence", quantite: 100, glucides: 4, insuline: 0.0),
                        Aliment(emoji: "🍞", nom: "Pain complet aux graines de tournesol et de lin", quantite: 60, glucides: 28, insuline: 1.5),
                    ]
                ),
            ]
        )
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.secondarySystemBackground))
}
