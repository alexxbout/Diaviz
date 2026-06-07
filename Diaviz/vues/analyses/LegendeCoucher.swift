//
//  LegendeCoucher.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import SwiftUI

/// Légende des icônes utilisées dans les tableaux du coucher (B2 / B3).
/// Discrète, en bas de section : grille 2 colonnes, petit texte secondaire.
/// Couvre uniquement les **icônes** (le texte des badges — dose, issue — est
/// explicite).
struct LegendeCoucher: View {

    private struct Item: Identifiable {
        let id = UUID()
        let systeme: String
        let libelle: String
        var couleur: Color = .secondary
    }

    private let items: [Item] = [
        Item(systeme: "flame.fill",     libelle: "Charge de la semaine"),
        Item(systeme: "arrow.up.right", libelle: "Tendance glycémie"),
        Item(systeme: "drop.fill",      libelle: "Insuline active"),
        Item(systeme: "fork.knife",     libelle: "Glucides pris"),
        Item(systeme: "figure.run",     libelle: "Sport (détail au tap)"),
    ]

    private let colonnes = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Légende")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: colonnes, alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.systeme)
                            .foregroundStyle(item.couleur)
                            .frame(width: 16)
                        Text(item.libelle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.caption2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Légende : flamme, charge de la semaine. Flèche, tendance de la glycémie. Goutte, insuline active. Couverts, glucides pris. Coureur, sport, détail au tap.")
    }
}

// MARK: - Aperçu

#Preview("Légende") {
    LegendeCoucher()
        .padding()
        .background(Color(.systemGroupedBackground))
}
