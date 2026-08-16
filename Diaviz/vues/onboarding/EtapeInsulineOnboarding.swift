//
//  EtapeInsulineOnboarding.swift
//  diaviz
//

import SwiftUI

/// Étape 3 de l'onboarding — insuline rapide/lente et durée d'action.
/// Reprise directe de `SectionInsuline`, identique à la sous-page
/// Réglages correspondante.
struct EtapeInsulineOnboarding: View {
    var body: some View {
        Form {
            SectionInsuline()
        }
        .formStyle(.grouped)
        // Le fond est porté par `OnboardingVue` pour tout l'écran d'un bloc.
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }
}

#if DEBUG
#Preview {
    EtapeInsulineOnboarding()
        .environment(ProfilService.mockVide())
}
#endif
