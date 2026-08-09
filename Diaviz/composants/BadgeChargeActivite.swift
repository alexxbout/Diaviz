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

    /// `true` → flamme + niveau écrit, inline, sans tap (lignes des tableaux).
    /// `false` → flamme seule, détail au tap (usages compacts).
    var avecLibelle: Bool = false

    @State private var afficherInfo = false

    var body: some View {
        if avecLibelle {
            badgeLibelle
        } else {
            badgeCompact
        }
    }

    // MARK: Inline (flamme + niveau)

    private var badgeLibelle: some View {
        HStack(spacing: 4) {
            Image(systemName: Self.symbole)
                .foregroundStyle(Self.couleur(charge))
            Text(charge.libelleCourt)
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activité de la semaine : \(charge.libelle)")
    }

    // MARK: Compact (flamme seule + popover)

    private var badgeCompact: some View {
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

    private static func couleur(_ charge: ChargeActivite) -> Color { charge.couleur }
}

// MARK: - Couleur d'intensité (partagée avec les chips de contexte)

extension ChargeActivite {
    /// Couleur d'intensité — gris neutre → bleu → orange → rouge. Source
    /// unique pour tous les usages (flamme du badge, chip flamme des lignes
    /// de soir, etc.).
    var couleur: Color {
        switch self {
        case .aucune:  return .gray
        case .calme:   return .blue
        case .moderee: return .orange
        case .intense: return .red
        }
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Badges charge") {
    HStack(spacing: 20) {
        BadgeChargeActivite(charge: .aucune)
        BadgeChargeActivite(charge: .calme)
        BadgeChargeActivite(charge: .moderee)
        BadgeChargeActivite(charge: .intense)
    }
    .padding()
}
#endif
