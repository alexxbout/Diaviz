//
//  LoaderPoints.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Trois points qui pulsent — utilisé pendant la génération du message
/// narratif LLM dans `SheetScoreMatin`.
///
/// Respecte « Réduire les animations » système : sans animation, les
/// trois points sont rendus statiques en opacité 0.5.
///
/// Implémentation partagée — auparavant dupliquée à l'identique sous
/// les noms `LoaderPoints` et `LoaderTroisPoints`.
struct LoaderPoints: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(0.5)
                }
            }
        } else {
            TimelineView(.periodic(from: .now, by: 0.4)) { contexte in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.secondary)
                            .frame(width: 8, height: 8)
                            .opacity(opacite(index: index, date: contexte.date))
                    }
                }
            }
        }
    }

    private func opacite(index: Int, date: Date) -> Double {
        let bucket = Int(date.timeIntervalSince1970 / 0.4) % 3
        return bucket == index ? 1.0 : 0.3
    }
}
