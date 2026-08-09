//
//  BoutonRadioIntensite.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

/// Bouton radio horizontal compact pour la sélection d'une intensité,
/// destiné à un usage **inline** (HStack des trois niveaux côte-à-côte).
///
/// Variante visuelle de la `CardRadioIntensite` privée à
/// `SheetNouvelleActivite` — on n'a pas la place ici pour la
/// description longue, donc on se limite au cercle + libellé.
///
/// Le tap couvre toute la zone (cible HIG ≥ 44pt grâce au padding
/// vertical), pas juste le cercle.
struct BoutonRadioIntensite: View {
    let intensite: IntensiteSport
    let selectionnee: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selectionnee
                    ? "largecircle.fill.circle"
                    : "circle"
                )
                .font(.callout)
                .foregroundStyle(selectionnee ? Color.accentColor : .secondary)
                .symbolRenderingMode(.hierarchical)

                Text(intensite.rawValue)
                    .font(.caption.weight(selectionnee ? .semibold : .regular))
                    .foregroundStyle(selectionnee ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(selectionnee
                        ? Color.accentColor.opacity(0.12)
                        : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(intensite.rawValue)
        .accessibilityAddTraits(selectionnee ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 8) {
        BoutonRadioIntensite(intensite: .faible, selectionnee: false) {}
        BoutonRadioIntensite(intensite: .moderee, selectionnee: true) {}
        BoutonRadioIntensite(intensite: .intense, selectionnee: false) {}
    }
    .padding()
}
#endif
