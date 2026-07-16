//
//  HeureRepasSection.swift
//  diaviz
//
//  Created by Alexandre on 05/07/2026.
//

import SwiftUI

/// Row "Date et heure du repas" de la `RepasSheet`. Toujours visible
/// (contrairement au site d'injection, la date/heure a un sens même sans
/// dose) — préremplie à l'instant actuel, réglable pour les saisies
/// rétroactives (repas d'un jour précédent, oublié puis saisi plus tard).
struct HeureRepasSection: View {

    @Binding var heure: Date

    var body: some View {
        Section {
            DatePicker(
                "Date et heure du repas",
                selection: $heure,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }
}

// MARK: - Aperçu

#Preview {
    @Previewable @State var heure = Date()
    Form {
        HeureRepasSection(heure: $heure)
    }
    .formStyle(.grouped)
}
