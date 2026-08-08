//
//  CarteRadioStructureEffort.swift
//  diaviz
//

import SwiftUI

/// Card radio pour choisir la structure de l'effort (continu/fractionné) —
/// même pattern que `CarteRadioIntensite` (radio + titre + description,
/// tap sur toute la card).
struct CarteRadioStructureEffort: View {
    let structure: StructureEffort
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
                    Text(structure.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(structure.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(selectionnee
                        ? Color.accentColor.opacity(0.10)
                        : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(
                        selectionnee ? Color.accentColor : .clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(structure.rawValue), \(structure.description)")
        .accessibilityAddTraits(selectionnee ? [.isSelected] : [])
    }
}
