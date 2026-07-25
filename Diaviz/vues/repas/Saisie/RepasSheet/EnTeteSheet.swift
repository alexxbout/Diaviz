//
//  EnTeteSheet.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// En-tête de la `RepasSheet` quand elle est étendue (medium / large).
/// Contient uniquement le titre principal — le récap aliments/glucides
/// (trop petit ici pour être utile) est maintenant affiché en gros dans
/// `ListeAlimentsSection`, au plus près des aliments qu'il résume.
///
/// La poignée de drag est gérée par la sheet elle-même via
/// `.presentationDragIndicator(.visible)` — on n'en ajoute pas ici.
struct EnTeteSheet: View {

    let nombreAliments: Int
    let totalGlucides: Double

    var body: some View {
        Text("Repas en cours")
            .font(.title2.bold())
            // VoiceOver lit déjà le texte, mais on précise le rôle d'en-tête.
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
    }
}

#Preview {
    EnTeteSheet(nombreAliments: 3, totalGlucides: 47.5)
        .padding()
}
