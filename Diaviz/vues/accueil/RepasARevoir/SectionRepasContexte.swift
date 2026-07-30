//
//  SectionRepasContexte.swift
//  diaviz
//

import SwiftUI

/// Section « Repas avec contexte » — affichée sur l'accueil sous « Repas à
/// revoir ». Liste en scroll horizontal les repas isolés (pas de récurrence
/// recherchée) portant un contexte libre (`Repas.contexteLibre`) et un
/// verdict mauvais. Réutilise `CarteRepasARevoir` — chaque carte a une seule
/// occurrence (pas de nuage de courbes passées) et affiche le contexte tel
/// quel via `RepasARevoir.contexteAffiche`.
///
/// Auto-masquée si le tableau est vide. Même pattern edge-to-edge que
/// `SectionRepasARevoir`.
struct SectionRepasContexte: View {

    let repas: [RepasARevoir]

    var body: some View {
        if !repas.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Repas avec contexte (\(repas.count))")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(repas) { item in
                            CarteRepasARevoir(repas: item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Aperçus

#Preview("Repas avec contexte") {
    ScrollView {
        SectionRepasContexte(repas: [
            RepasARevoir(
                aliments: [Aliment(emoji: "🍔", nom: "Fast-food", quantite: 300, glucides: 60, insuline: 5)],
                nombreOccurrences: 1,
                pointsOccurrencesPassees: [],
                pointsDerniereFois: (0...12).map { PointCourbeRepas(minutes: $0 * 15, glycemie: 100 + Double($0) * 8) },
                evenementMinutes: 90,
                evenementValeur: 210,
                estHypo: false,
                glucidesMin: 60,
                glucidesMax: 60,
                contexteAffiche: "Je prends la voiture"
            ),
        ])
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Repas avec contexte - Vide") {
    ScrollView {
        SectionRepasContexte(repas: [])
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
