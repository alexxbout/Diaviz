//
//  SectionInsuline.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « INSULINE » du profil — type d'insuline rapide (+ sa durée
/// d'action), puis type d'insuline lente.
///
/// La durée d'action (DIA) est **propre à l'insuline rapide** : elle est
/// placée juste sous le sélecteur de rapide et libellée explicitement
/// pour lever l'ambiguïté avec la lente. Slider 3–6h, pas 0,5, trois
/// repères (Fiasp / standard / longue). Sert au calcul de l'IOB.
struct SectionInsuline: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Section {
            // MARK: Insuline rapide + sa durée d'action (DIA)
            Picker("Insuline rapide", selection: bindingRapide) {
                ForEach(InsulineRapide.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)

            // DIA placée juste sous la rapide et libellée « (rapide) » :
            // ce paramètre ne concerne que l'insuline rapide (calcul IOB),
            // jamais la lente.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Durée d'action (rapide)")
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
                    Text("6h (longue)")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)

            // MARK: Insuline lente (pas de DIA — paramètre rapide uniquement)
            Picker("Insuline lente", selection: bindingLente) {
                ForEach(InsulineLente.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Insuline")
        } footer: {
            Text("La durée d'action concerne l'insuline rapide : elle détermine la durée de calcul de l'insuline active (IOB).")
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
