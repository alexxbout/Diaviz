//
//  SiteInjectionPicker.swift
//  insulog
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

// MARK: - Modèle

/// Zones anatomiques classiques pour une injection sous-cutanée d'insuline.
enum ZoneInjection: String, CaseIterable, Identifiable {
    case ventre = "Ventre"
    case cuisse = "Cuisse"
    case bras = "Bras"
    case fesse = "Fesse"

    var id: String { rawValue }
}

/// Côté ou position relative au sein de la zone.
enum CoteInjection: String, CaseIterable, Identifiable {
    case gauche = "Gauche"
    case centre = "Centre"
    case droite = "Droite"

    var id: String { rawValue }
}

/// Site d'injection complet (zone + côté), tel qu'affiché en résumé "Ventre gauche".
struct SiteInjection: Equatable, Hashable {
    var zone: ZoneInjection
    var cote: CoteInjection

    /// Libellé concaténé pour affichage dans une row.
    var libelle: String {
        "\(zone.rawValue) \(cote.rawValue.lowercased())"
    }

    /// Site par défaut proposé à l'ouverture de la sheet.
    static let parDefaut = SiteInjection(zone: .ventre, cote: .gauche)
}

// MARK: - Sheet de sélection

/// Sheet permettant à l'utilisateur de choisir un site d'injection
/// (combinaison zone × côté). Affiche un avertissement si la zone choisie
/// est la même que la dernière injection rapide.
struct SiteInjectionPicker: View {

    // MARK: Paramètres

    @Binding var site: SiteInjection
    /// Zone de la dernière injection rapide enregistrée (mockée pour l'instant).
    /// Si elle correspond à la zone actuellement sélectionnée, on affiche un warning.
    let derniereZoneRapide: ZoneInjection?

    @Environment(\.dismiss) private var dismiss

    // MARK: Corps

    var body: some View {
        NavigationStack {
            Form {
                sectionZone
                sectionCote
                if estMemeZone { sectionAvertissement }
            }
            .navigationTitle("Site d'injection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        // Plein écran pour avoir toutes les zones, le picker côté et un
        // éventuel warning visibles sans scroll.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Pas de Liquid Glass sur les sheets internes.
        .presentationBackground(Color(.systemGroupedBackground))
    }

    // MARK: Sous-vues

    private var sectionZone: some View {
        Section("Zone") {
            Picker("Zone", selection: $site.zone) {
                ForEach(ZoneInjection.allCases) { zone in
                    Text(zone.rawValue).tag(zone)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
        }
    }

    private var sectionCote: some View {
        Section("Côté") {
            Picker("Côté", selection: $site.cote) {
                ForEach(CoteInjection.allCases) { cote in
                    Text(cote.rawValue).tag(cote)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
        }
    }

    private var sectionAvertissement: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.body)
                Text("Même zone que la dernière injection rapide. Pensez à varier les sites pour éviter les lipodystrophies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Calculs

    private var estMemeZone: Bool {
        guard let derniereZoneRapide else { return false }
        return derniereZoneRapide == site.zone
    }
}

// MARK: - Aperçu

#Preview {
    @Previewable @State var site = SiteInjection.parDefaut
    Color.gray.opacity(0.2)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SiteInjectionPicker(site: $site, derniereZoneRapide: .ventre)
        }
}
