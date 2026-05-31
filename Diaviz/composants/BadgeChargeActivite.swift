//
//  BadgeChargeActivite.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import SwiftUI

/// Badge compact de la charge d'activité hebdomadaire : **un seul symbole**,
/// la **couleur** porte l'intensité (bleu tranquille → orange moyen → rouge
/// intense). Tap → popover avec un texte descriptif factuel.
///
/// Composant transverse, réutilisable partout où le contexte d'activité
/// éclaire une donnée (lignes du tableau d'endormissement, accueil, etc.).
struct BadgeChargeActivite: View {

    let charge: ChargeActivite

    @State private var afficherInfo = false

    var body: some View {
        Button {
            afficherInfo = true
        } label: {
            Image(systemName: Self.symbole)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Self.couleur(charge))
                .padding(6)
                .background(Self.couleur(charge).opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Charge d'activité de la semaine : \(charge.libelle). \(charge.descriptif)")
        .popover(isPresented: $afficherInfo) {
            HStack(spacing: 8) {
                Image(systemName: Self.symbole)
                    .foregroundStyle(Self.couleur(charge))
                VStack(alignment: .leading, spacing: 1) {
                    Text(charge.libelle)
                        .font(.subheadline.weight(.semibold))
                    Text(charge.descriptif)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .fixedSize()
            .presentationCompactAdaptation(.popover)
        }
    }

    /// Symbole unique, constant — c'est la couleur qui distingue l'intensité.
    private static let symbole = "flame.fill"

    private static func couleur(_ charge: ChargeActivite) -> Color {
        switch charge {
        case .aucune:  return .gray
        case .calme:   return .blue
        case .moderee: return .orange
        case .intense: return .red
        }
    }
}

// MARK: - Aperçu

#Preview("Badges charge") {
    HStack(spacing: 20) {
        BadgeChargeActivite(charge: .aucune)
        BadgeChargeActivite(charge: .calme)
        BadgeChargeActivite(charge: .moderee)
        BadgeChargeActivite(charge: .intense)
    }
    .padding()
}
