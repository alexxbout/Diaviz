//
//  EtapePoidsOnboarding.swift
//  diaviz
//

import SwiftUI

/// Étape 2 de l'onboarding — poids, seule étape à ne **pas** reprendre
/// un composant Réglages : un gros chiffre + stepper est plus lisible
/// pour une saisie isolée en plein écran que le `TextField` compact de
/// `SectionInformationsBase`, pensé lui pour un `Form` dense.
struct EtapePoidsOnboarding: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(poidsAffiche)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: service.profil.poidsKg)
                Text("kg")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 32) {
                Button {
                    ajuster(-1)
                } label: {
                    Image(systemName: "minus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())

                Text("Passer si vous ne le connaissez pas")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    ajuster(1)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        // Petit clic à chaque pas du stepper — le contrôle le plus manipulé
        // de l'onboarding, et sans retour tactile on ne sait pas si l'appui
        // a porté quand on ajuste sans regarder.
        .sensoryFeedback(.selection, trigger: service.profil.poidsKg)
    }

    private var poidsAffiche: String {
        guard let valeur = service.profil.poidsKg else { return "—" }
        return valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur).replacingOccurrences(of: ".", with: ",")
    }

    private func ajuster(_ delta: Double) {
        let actuel = service.profil.poidsKg ?? 70
        let nouveau = min(300, max(20, actuel + delta))
        service.mettreAJour { $0.poidsKg = nouveau }
    }
}

#if DEBUG
#Preview {
    EtapePoidsOnboarding()
        .environment(ProfilService.mockVide())
}
#endif
