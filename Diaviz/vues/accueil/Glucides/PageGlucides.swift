//
//  PageGlucides.swift
//  diaviz
//

import Charts
import SwiftUI

/// Page de détail « Glucides » — pushée depuis `CarteGlucidesSemaine`. Gros
/// chiffre + delta en tête, histogramme des 14 derniers jours (7 « semaine
/// dernière » en teinte atténuée, 7 « cette semaine » en teinte pleine).
///
/// Reste volontairement simple : une seule page, un seul graphique, aucune
/// interaction de sélection — la carte accueil donne déjà l'essentiel, cette
/// page ne fait qu'étaler la série sous-jacente.
struct PageGlucides: View {

    let synthese: SyntheseGlucidesHebdo

    private let teinte = Color.brown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                enTeteStats
                graphique
                Label(
                    "14 derniers jours. Glucides déclarés dans les repas, hors repas mis en pause.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Glucides")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var enTeteStats: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(synthese.moyenneCetteSemaine.rounded()))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("g / jour en moyenne")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(synthese.libelleDelta.capitalizedFirstLetter)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private var graphique: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                legendePastille(couleur: teinte.opacity(0.35), texte: "Semaine dernière")
                legendePastille(couleur: teinte, texte: "Cette semaine")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Chart {
                ForEach(Array(synthese.serieJournaliere.enumerated()), id: \.offset) { index, point in
                    BarMark(
                        x: .value("Jour", point.jour, unit: .day),
                        y: .value("Glucides", point.totalGlucides)
                    )
                    .foregroundStyle(index >= 7 ? teinte : teinte.opacity(0.35))
                    .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private func legendePastille(couleur: Color, texte: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(couleur).frame(width: 7, height: 7)
            Text(texte)
        }
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    NavigationStack {
        PageGlucides(synthese: .mockCroissance)
    }
}

#Preview("Sombre") {
    NavigationStack {
        PageGlucides(synthese: .mockCroissance)
    }
    .preferredColorScheme(.dark)
}

#Preview("Texte agrandi") {
    NavigationStack {
        PageGlucides(synthese: .mockCroissance)
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
