//
//  BoutonValiderRepas.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Bouton primaire flottant en bas de la sheet pour valider le repas.
///
/// Pensé pour être posé via `.safeAreaInset(edge: .bottom)` sur la vue
/// principale, avec un fond `.regularMaterial` qui lit naturellement comme
/// du verre sur iOS 26.
struct BoutonValiderRepas: View {

    let nombreAliments: Int
    let onValider: () -> Void

    /// Trigger pour le retour haptique de succès.
    @State private var triggerHaptique: Int = 0
    /// Trigger pour le bounce de l'icône au tap.
    @State private var triggerBounce: Int = 0

    private var desactive: Bool { nombreAliments == 0 }

    private var libelle: String {
        let mot = nombreAliments == 1 ? "aliment" : "aliments"
        return "Enregistrer le repas (\(nombreAliments) \(mot))"
    }

    var body: some View {
        Button {
            triggerBounce += 1
            triggerHaptique += 1
            onValider()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, value: triggerBounce)
                Text(libelle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.accentColor)
        .foregroundStyle(.white)
        .disabled(desactive)
        // Haptic .success uniquement quand le bouton est actif.
        .sensoryFeedback(.success, trigger: triggerHaptique)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        // Background glass : la sheet à l'étage du dessous a déjà sa Liquid Glass,
        // ici on ajoute juste un voile material pour bien démarquer la zone CTA.
        .background(.regularMaterial)
        .accessibilityHint(desactive ? "Ajoutez au moins un aliment pour activer ce bouton" : "Valide et enregistre le repas en cours")
    }
}

#Preview {
    VStack {
        Spacer()
        BoutonValiderRepas(nombreAliments: 3) {}
    }
    .background(Color(.systemGroupedBackground))
}
