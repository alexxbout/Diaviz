//
//  CarteRadioIntention.swift
//  diaviz
//

import SwiftUI

/// Card radio pour choisir l'intention d'un resucrage — même pattern que
/// `CarteRadioIntensite`/`CarteRadioStructureEffort` (radio + titre +
/// description, tap sur toute la card).
struct CarteRadioIntention: View {
    let intention: IntentionResucrage
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

                Image(systemName: intention.icone)
                    .font(.body)
                    .foregroundStyle(intention.couleur)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(intention.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(intention.description)
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
        .accessibilityLabel("\(intention.rawValue), \(intention.description)")
        .accessibilityAddTraits(selectionnee ? [.isSelected] : [])
    }
}
