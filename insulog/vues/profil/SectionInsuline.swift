//
//  SectionInsuline.swift
//  insulog
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « INSULINE » du profil — type d'insuline rapide, type
/// d'insuline lente, et durée d'action (DIA) ajustable au slider.
///
/// La DIA est exposée comme un slider 3–6h avec pas 0,5 et trois
/// repères contextuels (Fiasp / standard / lente) pour aider à se
/// situer. Footer rappelant le rôle du paramètre dans le calcul de
/// l'IOB.
struct SectionInsuline: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Section {
            // MARK: Insuline rapide
            Picker("Insuline rapide", selection: bindingRapide) {
                ForEach(InsulineRapide.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)

            // MARK: Insuline lente
            Picker("Insuline lente", selection: bindingLente) {
                ForEach(InsulineLente.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)

            // MARK: DIA
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Durée d'action")
                    Spacer()
                    Text(formateHeures(service.profil.dureeActionInsulineHeures))
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2),
                                   value: service.profil.dureeActionInsulineHeures)
                }

                Slider(
                    value: bindingDIA,
                    in: 3...6,
                    step: 0.5
                )

                HStack {
                    Text("3h (Fiasp)")
                    Spacer()
                    Text("4h (standard)")
                    Spacer()
                    Text("6h (lente)")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Insuline")
        } footer: {
            Text("Détermine la durée de calcul de l'insuline active (IOB).")
        }
    }

    // MARK: - Bindings

    private var bindingRapide: Binding<InsulineRapide> {
        Binding(
            get: { service.profil.insulineRapide },
            set: { nouveau in
                service.mettreAJour { $0.insulineRapide = nouveau }
            }
        )
    }

    private var bindingLente: Binding<InsulineLente> {
        Binding(
            get: { service.profil.insulineLente },
            set: { nouveau in
                service.mettreAJour { $0.insulineLente = nouveau }
            }
        )
    }

    private var bindingDIA: Binding<Double> {
        Binding(
            get: { service.profil.dureeActionInsulineHeures },
            set: { nouveau in
                service.mettreAJour { $0.dureeActionInsulineHeures = nouveau }
            }
        )
    }

    // MARK: - Format

    /// Formate la DIA en « 4h » ou « 4,5h » selon qu'elle a une
    /// décimale ou pas. Gardé interne car n'a pas d'usage ailleurs.
    private func formateHeures(_ valeur: Double) -> String {
        if valeur == floor(valeur) {
            return "\(Int(valeur))h"
        }
        return String(format: "%.1fh", valeur)
            .replacingOccurrences(of: ".", with: ",")
    }
}
