//
//  MicroVisuelInsight.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Petit visuel placé entre le header et le message d'une `CarteInsight`.
/// Hauteur cible ~30pt — calée pour que les 4 variantes occupent une
/// même bande horizontale, ce qui aligne visuellement les cartes au
/// sein du TabView paginé (160pt fixes).
///
/// Le rendu est piloté par `MicroVisuelType` ; ajouter un type consiste
/// à étendre l'enum + une branche du switch ici.
struct MicroVisuelInsight: View {

    let type: MicroVisuelType
    /// Couleur d'accent — héritée de la catégorie de la carte parente,
    /// appliquée aux valeurs en avant et aux barres du mini-chart.
    let couleur: Color

    var body: some View {
        switch type {

        // MARK: Pourcentage : « Ratio → -25% »
        case .pourcentage(let label, let valeur):
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(valeur)
                    .font(.title3.bold())
                    .foregroundStyle(couleur)
                    .monospacedDigit()
            }
            .frame(height: 30)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label) : \(valeur)")

        // MARK: Mini bar chart — barres verticales + seuil horizontal
        case .miniBarres(let hauteurs):
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(hauteurs.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(couleur)
                        .frame(width: 8, height: h)
                }
            }
            .frame(height: 30)
            .overlay(alignment: .bottom) {
                // Trait fin gris symbolisant le seuil glycémique à
                // 200 mg/dL — dépassé par les barres pour visualiser
                // les pics. Offset négatif pour le placer ~2/3 haut.
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 0.5)
                    .offset(y: -18)
            }
            .accessibilityElement()
            .accessibilityLabel("\(hauteurs.count) repas, plusieurs ont dépassé le seuil")

        // MARK: Préfixe + flèche directionnelle + label coloré
        case .fleche(let prefix, let direction, let label):
            HStack(spacing: 8) {
                Text(prefix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: direction)
                    .font(.title3)
                    .foregroundStyle(couleur)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(couleur)
            }
            .frame(height: 30)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(prefix), \(label)")

        // MARK: Aucun visuel — le message du dessus prend la place
        case .aucun:
            EmptyView()
        }
    }
}

// MARK: - Aperçus

#Preview("Pourcentage bleu") {
    MicroVisuelInsight(
        type: .pourcentage(label: "Ratio", valeur: "-25%"),
        couleur: .blue
    )
    .padding()
}

#Preview("Mini barres orange") {
    MicroVisuelInsight(
        type: .miniBarres(hauteurs: [28, 22, 32, 25]),
        couleur: .orange
    )
    .padding()
}

#Preview("Flèche descendante orange") {
    MicroVisuelInsight(
        type: .fleche(prefix: "3 nuits", direction: "arrow.down.right", label: "↘ tendance basse"),
        couleur: .orange
    )
    .padding()
}
