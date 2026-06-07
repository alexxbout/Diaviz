//
//  BadgeSport.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import SwiftUI

/// Badge sport compact : 🏃 seule, le détail de la séance (type · intensité ·
/// durée) s'affiche dans un **popover** au tap — l'info est trop riche pour
/// tenir en valeur inline.
struct BadgeSport: View {

    let seance: SportResume

    @State private var afficher = false

    var body: some View {
        Button {
            afficher = true
        } label: {
            Image(systemName: "figure.run")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sport : \(seance.resume)")
        .popover(isPresented: $afficher) {
            HStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .foregroundStyle(.secondary)
                Text(seance.resume)
                    .font(.footnote)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .fixedSize()
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Aperçu

#Preview("Badge sport") {
    BadgeSport(seance: SportResume(type: "Course", intensite: "modéré", dureeMinutes: 45))
        .padding()
}
