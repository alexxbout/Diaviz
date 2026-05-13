//
//  SectionPreferencesAvancees.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « PRÉFÉRENCES AVANCÉES » — repliée par défaut dans un
/// `DisclosureGroup` parce que peu de gens y touchent.
///
/// Pour l'instant un seul réglage : la marge d'alerte de dose. On
/// hostera ici les options « pause d'analyses », « format glycémie
/// (mg/dL vs mmol/L) », etc. plus tard sans avoir à toucher la
/// hiérarchie de la sheet.
struct SectionPreferencesAvancees: View {

    @Environment(ProfilService.self) private var service

    /// État local d'ouverture du groupe — par défaut fermé. Pas de
    /// persistance : c'est une préférence visuelle de session, pas un
    /// paramètre profil.
    @State private var ouvert: Bool = false

    var body: some View {
        Section {
            DisclosureGroup("Préférences avancées", isExpanded: $ouvert) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Marge d'alerte dose")
                        Spacer()
                        Text(formate(service.profil.preferencesAvancees.margeAlerteDose))
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(
                                .easeOut(duration: 0.15),
                                value: service.profil.preferencesAvancees.margeAlerteDose
                            )
                        Stepper(
                            "",
                            value: bindingMarge,
                            in: 0.5...3,
                            step: 0.5
                        )
                        .labelsHidden()
                    }

                    Text("""
                    Écart toléré entre la dose saisie et la dose \
                    suggérée par votre ratio avant d'afficher un \
                    avertissement.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Binding

    private var bindingMarge: Binding<Double> {
        Binding(
            get: { service.profil.preferencesAvancees.margeAlerteDose },
            set: { nouvelle in
                service.mettreAJour {
                    $0.preferencesAvancees.margeAlerteDose = nouvelle
                }
            }
        )
    }

    // MARK: - Format

    /// Affiche « ± 1u » ou « ± 1,5u » — la virgule plutôt que le point
    /// pour rester cohérent avec la locale française.
    private func formate(_ valeur: Double) -> String {
        let formate = valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
                .replacingOccurrences(of: ".", with: ",")
        return "± \(formate)u"
    }
}
