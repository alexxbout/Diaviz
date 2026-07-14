//
//  ChipsSoiree.swift
//  diaviz
//

import SwiftUI

// MARK: - Chip de contexte

/// Petite pastille de contexte — SF Symbol + texte. La teinte **accent**
/// (indigo) marque la correction, seule à porter une couleur (frontière
/// B2/B3). Partagée entre `LigneSoirCoucher` et la sheet détail de soirée.
struct ChipContexte: View {

    struct Modele: Identifiable {
        let id = UUID()
        let symbole: String
        let texte: String
        let accent: Bool
    }

    let chip: Modele

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: chip.symbole)
            Text(chip.texte).monospacedDigit()
        }
        .font(.system(size: 11.5, weight: chip.accent ? .medium : .regular))
        .foregroundStyle(chip.accent ? Color.indigo : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            chip.accent ? Color.indigo.opacity(0.14) : Color(.tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
    }
}

// MARK: - Chip charge d'activité

/// Pastille dédiée à la charge — mêmes proportions que `ChipContexte`, mais
/// avec une flamme **colorée par intensité** en tête (bleu calme → orange
/// modérée → rouge intense). Couleur partagée avec `BadgeChargeActivite`
/// (`ChargeActivite.couleur`, source unique).
struct ChipCharge: View {

    let charge: ChargeActivite

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .foregroundStyle(charge.couleur)
            Text(charge.libelleCourt)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activité de la semaine : \(charge.libelle)")
    }
}

// MARK: - Aperçu

#Preview("Chips soirée") {
    FlowLayout(spacing: 6) {
        ChipCharge(charge: .intense)
        ChipContexte(chip: .init(symbole: "syringe.fill", texte: "correction +4u", accent: true))
        ChipContexte(chip: .init(symbole: "drop.fill", texte: "IOB 1.5U", accent: false))
        ChipContexte(chip: .init(symbole: "figure.run", texte: "Course · 45 min", accent: false))
        ChipContexte(chip: .init(symbole: "fork.knife", texte: "15g", accent: false))
    }
    .padding()
}
