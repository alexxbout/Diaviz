//
//  CarteDernierRepas.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import SwiftUI

/// Carte "Repas" — quatrième carte de la grille d'accueil. Présente
/// les glucides du dernier repas, le temps écoulé depuis (rafraîchi
/// à la minute via `TimelineView`), et une ligne de **3 emojis max**
/// reprenant les aliments du repas — équivalent visuel du badge de
/// la carte Injection, pour équilibrer la grille.
struct CarteDernierRepas: View {

    /// Glucides en grammes — affichés à l'entier ("45g", pas "45.0g").
    let glucides: Double

    /// Temps écoulé en secondes depuis la fin du repas. Sert de base
    /// au rafraîchissement périodique, comme pour `CarteDerniereInjection`.
    let depuis: TimeInterval

    /// Emojis des aliments du repas. Tronqués aux 3 premiers — la
    /// largeur de carte ne permet pas plus, et 3 emojis suffisent à
    /// donner le ton du repas (pain/fromage/lait, salade/avocat, …).
    let emojis: [String]

    var body: some View {
        // Référence temporelle figée à l'apparition de la vue —
        // comme `CarteDerniereInjection`, on évite la dérive.
        let ancre = Date().addingTimeInterval(-depuis)

        CarteMetriqueShell {
            // VStack spacing 0 + paddings explicites — voir la note
            // sur l'alignement des valeurs dans `CarteHypos`.
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Ligne icône + titre (haut)
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.footnote)
                        .foregroundStyle(couleurIcone)
                        .accessibilityHidden(true)
                    Text("Repas")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                // MARK: Valeur principale + unité collée (Y fixe)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(glucides.rounded()))")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("g")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .padding(.top, 24)

                Spacer(minLength: 0)

                // MARK: Bloc bas — temps relatif + emojis, ancrés au
                // bas de la carte (pendant visuel du badge Injection).
                VStack(alignment: .leading, spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 60)) { contexte in
                        Text(tempsRelatif(depuis: ancre, maintenant: contexte.date))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !emojis.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(emojis.prefix(3), id: \.self) { emoji in
                                Text(emoji)
                                    .font(.title3)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Dernier repas : \(Int(glucides.rounded())) grammes de glucides, \(tempsRelatif(depuis: ancre))"
        )
    }

    // MARK: - Apparence

    /// Vert foncé "repas" (#639922) — code couleur dédié aux aliments
    /// dans la charte, distinct du vert plus clair des hypos.
    private var couleurIcone: Color {
        Color(red: 0x63 / 255, green: 0x99 / 255, blue: 0x22 / 255)
    }

}

// MARK: - Aperçus

#Preview("Repas - Avec emojis") {
    CarteDernierRepas(
        glucides: 72,
        depuis: 4080,
        emojis: ["🍞", "🧀", "🥛"]
    )
    .frame(width: 170, height: 180)
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Repas - Sans emoji") {
    CarteDernierRepas(
        glucides: 45,
        depuis: 7200,
        emojis: []
    )
    .frame(width: 170, height: 180)
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Repas - 5 emojis (tronqué)") {
    CarteDernierRepas(
        glucides: 78,
        depuis: 60 * 60 + 60 * 10,
        emojis: ["🍝", "🧀", "🥖", "🍷", "🍰"]
    )
    .frame(width: 170, height: 180)
    .padding()
    .background(Color(.systemGroupedBackground))
}
