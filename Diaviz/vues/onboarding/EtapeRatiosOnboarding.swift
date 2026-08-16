//
//  EtapeRatiosOnboarding.swift
//  diaviz
//

import SwiftUI

/// Étape 4 (dernière) de l'onboarding — ratio de base et ratio de
/// correction. Reprise directe de `SectionRatios` +
/// `SectionRatioCorrection`, sans `SectionRatiosSport` : les ratios
/// sport se règlent plus tard, depuis le profil.
struct EtapeRatiosOnboarding: View {
    var body: some View {
        Form {
            SectionRatios()
            SectionRatioCorrection()
        }
        .formStyle(.grouped)
        // Le fond est porté par `OnboardingVue` pour tout l'écran d'un bloc.
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }
}

#if DEBUG
#Preview {
    EtapeRatiosOnboarding()
        .environment(ProfilService.mockVide())
}
#endif
