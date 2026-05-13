//
//  EnTeteSheet.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// En-tête de la `RepasSheet` quand elle est étendue (medium / large).
/// Contient le titre principal et un récap rapide aliments + glucides.
///
/// La poignée de drag est gérée par la sheet elle-même via
/// `.presentationDragIndicator(.visible)` — on n'en ajoute pas ici.
struct EnTeteSheet: View {

    let nombreAliments: Int
    let totalGlucides: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Repas en cours")
                .font(.title2.bold())
                // VoiceOver lit déjà le texte, mais on précise le rôle d'en-tête.
                .accessibilityAddTraits(.isHeader)

            Text(sousTitre)
                .font(.caption)
                .foregroundStyle(.secondary)
                // Anime le changement de chiffre comme un compteur.
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: totalGlucides)
                .animation(.spring(response: 0.3), value: nombreAliments)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    /// "X aliments • Y.Yg glucides"
    private var sousTitre: String {
        let mot = nombreAliments == 1 ? "aliment" : "aliments"
        return "\(nombreAliments) \(mot) • \(String(format: "%.1f", totalGlucides))g glucides"
    }
}

#Preview {
    EnTeteSheet(nombreAliments: 3, totalGlucides: 47.5)
        .padding()
}
