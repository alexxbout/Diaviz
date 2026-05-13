//
//  IndicateurTapLong.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Indicateur visuel compact (icône + légende textuelle courte) avec
/// popover au tap long. Utilisé là où l'icône seule serait peu parlante
/// — par exemple dans `MiniCourbeReponse` pour signaler les états
/// `enAttente` et `donneesManquantes`, où le symbole a besoin d'un
/// libellé explicite (« 1h30 », « Pas de CGM ») et d'un message de
/// détail accessible au tap long.
///
/// Le tap simple est laissé à la row parente (pas géré ici).
struct IndicateurTapLong: View {
    let systemImage: String
    let legendeTexte: String
    let descriptionAccessibilite: String
    let messageTooltip: String

    @State private var afficheTooltip = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            Text(legendeTexte)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Tap simple → laissé à la row parente. Tap long (≥ 0.5s) → popover.
        .onLongPressGesture(minimumDuration: 0.5) {
            afficheTooltip = true
        }
        .popover(isPresented: $afficheTooltip, arrowEdge: .bottom) {
            Text(messageTooltip)
                .font(.caption)
                .padding(8)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityElement()
        .accessibilityLabel(descriptionAccessibilite)
        .accessibilityHint("Tap long pour plus de détails")
    }
}
