//
//  SectionRatioCorrection.swift
//  insulog
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « RATIO DE CORRECTION » — ISF (Insulin Sensitivity Factor)
/// optionnel exprimé en mg/dL baissés par 1 unité d'insuline rapide.
///
/// Optionnel : un certain nombre de patients ne le connaissent pas, et
/// l'app reste utile sans (les analyses statistiques peuvent le
/// re-déduire empiriquement).
struct SectionRatioCorrection: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Section {
            HStack {
                Text("1u baisse de")
                Spacer()
                Text(affichage(service.profil.ratioCorrection))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15),
                               value: service.profil.ratioCorrection)
                    .foregroundStyle(
                        service.profil.ratioCorrection == nil
                            ? .secondary : .primary
                    )
                Stepper(
                    "",
                    value: bindingValeur,
                    in: 10...100,
                    step: 5
                )
                .labelsHidden()
            }
        } header: {
            Text("Ratio de correction")
        } footer: {
            Text("""
            Aussi appelé ISF (Insulin Sensitivity Factor). Utilisé \
            pour analyser vos corrections. Demandez à votre médecin \
            si vous ne le connaissez pas.
            """)
        }
    }

    // MARK: - Binding

    /// Comme pour les ratios glucides, on travaille via un binding
    /// non-optionnel adossé au modèle optionnel : la première
    /// interaction du stepper fixe une valeur.
    private var bindingValeur: Binding<Double> {
        Binding(
            get: { service.profil.ratioCorrection ?? 40 },
            set: { nouveau in
                service.mettreAJour { $0.ratioCorrection = nouveau }
            }
        )
    }

    private func affichage(_ valeur: Double?) -> String {
        guard let valeur else { return "Non défini" }
        return "\(Int(valeur)) mg/dL"
    }
}
