//
//  DetailsSection.swift
//  insulog
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Section "DÉTAILS" repliable de la `RepasSheet`.
/// Quand fermée : résumé compact "Injection à HH:MM · Site".
/// Quand ouverte : DatePicker pour l'heure + sélection du site (avec sheet).
struct DetailsSection: View {

    @Binding var heureInjection: Date
    @Binding var siteInjection: SiteInjection
    /// Zone de la dernière injection rapide (mockée), utilisée pour le warning.
    let derniereZoneRapide: ZoneInjection?

    @State private var ouvert: Bool = false
    @State private var afficherPickerSite: Bool = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $ouvert) {
                heureRow
                siteRow
            } label: {
                if ouvert {
                    Text("Détails")
                        .font(.body)
                } else {
                    // Résumé compact quand fermé.
                    HStack {
                        Text("Détails")
                            .font(.body)
                        Spacer()
                        Text(resumeCompact)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $afficherPickerSite) {
            SiteInjectionPicker(site: $siteInjection, derniereZoneRapide: derniereZoneRapide)
        }
    }

    // MARK: - Rows internes

    private var heureRow: some View {
        HStack {
            Text("Heure d'injection")
                .font(.body)
            Spacer()
            DatePicker(
                "Heure d'injection",
                selection: $heureInjection,
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
    }

    private var siteRow: some View {
        HStack {
            Text("Site d'injection")
                .font(.body)
            Spacer()
            Button {
                afficherPickerSite = true
            } label: {
                HStack(spacing: 6) {
                    if memeZoneQueDerniere {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    Text(siteInjection.libelle)
                        .font(.body)
                        .foregroundStyle(.tint)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Site d'injection : \(siteInjection.libelle)")
            .accessibilityHint("Touchez deux fois pour changer de site")
        }
    }

    // MARK: - Calculs

    private var memeZoneQueDerniere: Bool {
        guard let derniereZoneRapide else { return false }
        return derniereZoneRapide == siteInjection.zone
    }

    private var resumeCompact: String {
        let formatHeure = heureInjection.formatted(date: .omitted, time: .shortened)
        return "Injection à \(formatHeure) · \(siteInjection.libelle)"
    }
}
