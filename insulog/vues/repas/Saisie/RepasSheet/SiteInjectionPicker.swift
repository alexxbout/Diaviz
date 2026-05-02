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

    /// Emoji associé à la zone — utilisé par le sélecteur en cartes et
    /// réutilisable ailleurs (résumé de timeline, historique, notifications).
    var emoji: String {
        switch self {
        case .ventre: return "🫄"
        case .cuisse: return "🦵"
        case .bras:   return "💪"
        case .fesse:  return "🍑"
        }
    }
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
            .sensoryFeedback(.selection, trigger: site.zone)
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

    /// Grille 2×2 de cartes sélectionnables (emoji + label) — pattern
    /// inspiré de l'app web. La row est "custom" : on retire les insets
    /// par défaut du `Form` pour contrôler le padding nous-mêmes.
    private var sectionZone: some View {
        Section("Zone") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(ZoneInjection.allCases) { zone in
                    CarteZone(
                        zone: zone,
                        estSelectionnee: site.zone == zone
                    ) {
                        site.zone = zone
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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

// MARK: - Carte de zone

/// Carte sélectionnable d'une zone d'injection (emoji héro + label).
/// État sélectionné : fond accent à `0.18` d'opacité + bordure 2pt accent.
/// État neutre : fond `secondarySystemGroupedBackground` (cell standard).
private struct CarteZone: View {

    let zone: ZoneInjection
    let estSelectionnee: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if reduceMotion {
                onTap()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    onTap()
                }
            }
        } label: {
            VStack(spacing: 8) {
                // Emoji "héro" en taille fixe — la lisibilité Dynamic Type
                // est portée par le label en dessous (.callout).
                Text(zone.emoji)
                    .font(.system(size: 40))

                Text(zone.rawValue)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(fond, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(bordure)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(zone.rawValue)
        .accessibilityAddTraits(estSelectionnee ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Touchez deux fois pour choisir cette zone")
    }

    private var fond: Color {
        estSelectionnee
            ? Color.accentColor.opacity(0.18)
            : Color(.secondarySystemGroupedBackground)
    }

    @ViewBuilder
    private var bordure: some View {
        if estSelectionnee {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
        }
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
