//
//  DetailsSection.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Row "Site d'injection" de la `RepasSheet`. Visible uniquement quand une
/// dose est saisie — sans injection, le site n'a pas de sens. Tap ouvre la
/// sheet de sélection (présentée par le parent pour éviter l'auto-dismiss
/// au 1er tap, cf. RepasSheet).
struct DetailsSection: View {

    @Binding var siteInjection: SiteInjection
    /// Zone de la dernière injection rapide (mockée), utilisée pour le warning.
    let derniereZoneRapide: ZoneInjection?
    /// Demande au parent (RepasSheet) de présenter la sheet de sélection de
    /// site. La sheet vit à la racine du body parent — sinon SwiftUI démonte
    /// sa présentation au premier rebuild du Form (auto-dismiss au 1er tap).
    let onOuvrirSitePicker: () -> Void

    var body: some View {
        Section {
            Button {
                onOuvrirSitePicker()
            } label: {
                HStack(spacing: 8) {
                    Text("Site d'injection")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Site d'injection : \(siteInjection.libelle)")
            .accessibilityHint("Touchez deux fois pour changer de site")
        }
    }

    private var memeZoneQueDerniere: Bool {
        guard let derniereZoneRapide else { return false }
        return derniereZoneRapide == siteInjection.zone
    }
}

// MARK: - Aperçu

#Preview("Site standard") {
    @Previewable @State var site = SiteInjection.parDefaut
    Form {
        DetailsSection(
            siteInjection: $site,
            derniereZoneRapide: .cuisse,
            onOuvrirSitePicker: {}
        )
    }
    .formStyle(.grouped)
}

#Preview("Avertissement même zone") {
    @Previewable @State var site = SiteInjection(zone: .ventre, cote: .gauche)
    Form {
        DetailsSection(
            siteInjection: $site,
            derniereZoneRapide: .ventre,
            onOuvrirSitePicker: {}
        )
    }
    .formStyle(.grouped)
}
