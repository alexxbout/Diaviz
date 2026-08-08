//
//  BoutonTypeSport.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Case tappable de la grille de types de sport, utilisée dans
/// `SheetNouvelleActivite`. Carré ~80pt avec icône SF Symbol + libellé
/// centrés ; bordure et fond accent en sélection.
struct BoutonTypeSport: View {
    let type: TypeSport
    let selectionne: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.icone)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(selectionne ? Color.accentColor : .primary)
                Text(type.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(selectionne
                        ? Color.accentColor.opacity(0.15)
                        : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(
                        selectionne ? Color.accentColor : .clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.rawValue)
        .accessibilityAddTraits(selectionne ? [.isSelected] : [])
    }
}
