//
//  CarteRadioIntensite.swift
//  insulog
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Card empilée verticalement — radio button + titre + description,
/// utilisée dans `SheetNouvelleActivite`. Le tap sur n'importe quelle
/// zone de la card sélectionne, pas uniquement le radio (cible plus
/// large, conforme HIG 44pt).
///
/// Variante « grand format » de `BoutonRadioIntensite` (compact,
/// inline) — la `CarteRadioIntensite` est utilisée dans la sheet de
/// création où on a la place pour afficher la description longue.
struct CarteRadioIntensite: View {
    let intensite: IntensiteSport
    let selectionnee: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selectionnee
                    ? "largecircle.fill.circle"
                    : "circle"
                )
                .font(.title3)
                .foregroundStyle(selectionnee ? Color.accentColor : .secondary)
                .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(intensite.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(intensite.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectionnee
                        ? Color.accentColor.opacity(0.10)
                        : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selectionnee ? Color.accentColor : .clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(intensite.rawValue), \(intensite.description)")
        .accessibilityAddTraits(selectionnee ? [.isSelected] : [])
    }
}
