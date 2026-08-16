//
//  EtapeIdentiteOnboarding.swift
//  diaviz
//

import SwiftUI

/// Étape 1 de l'onboarding — photo de profil et prénom.
///
/// Réutilise `SectionPhotoProfil` telle quelle (identique à la sheet
/// Profil). Le champ prénom reprend le binding et l'indicateur
/// « Requis » de `SectionInformationsBase`, isolé ici parce que cette
/// section couple prénom **et** poids — le poids a sa propre étape
/// dédiée (`EtapePoidsOnboarding`) avec une saisie plus visuelle.
struct EtapeIdentiteOnboarding: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Form {
            SectionPhotoProfil()

            Section("Informations de base") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Votre prénom", text: bindingPrenom)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()

                    if prenomVide {
                        Text("Requis")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Le fond est porté par `OnboardingVue` pour tout l'écran d'un bloc.
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private var bindingPrenom: Binding<String> {
        Binding(
            get: { service.profil.prenom },
            set: { nouveau in
                service.mettreAJour { $0.prenom = nouveau }
            }
        )
    }

    private var prenomVide: Bool {
        service.profil.prenom
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

#if DEBUG
#Preview {
    EtapeIdentiteOnboarding()
        .environment(ProfilService.mockVide())
}
#endif
