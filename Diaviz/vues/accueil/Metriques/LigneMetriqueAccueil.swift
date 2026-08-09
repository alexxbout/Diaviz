//
//  LigneMetriqueAccueil.swift
//  diaviz
//

import SwiftUI

/// Row compacte partagée par les 4 métriques d'accueil (« Aperçu du jour ») :
/// badge icône carré à gauche, titre + sous-titre au centre, valeur à droite.
///
/// Remplace l'ancienne grille 2×2 (cartes hautes avec beaucoup de vide,
/// icônes emoji mêlées à des SF Symbols) par une liste une-colonne dense,
/// style réglages iOS — chaque row occupe exactement la hauteur de son
/// contenu, sans espace mort.
struct LigneMetriqueAccueil<Trailing: View>: View {

    let icone: String
    let couleurIcone: Color
    let couleurFondIcone: Color
    let titre: String
    let sousTitre: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            badgeIcone

            VStack(alignment: .leading, spacing: 1) {
                Text(titre)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(sousTitre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    private var badgeIcone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(couleurFondIcone)
            Image(systemName: icone)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(couleurIcone)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

/// Valeur numérique + unité — trailing standard des rows (ex. "14" + "u").
struct ValeurMetriqueAccueil: View {
    let valeur: String
    let unite: String
    var couleur: Color = .primary

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(valeur)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(couleur)
            Text(unite)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        LigneMetriqueAccueil(
            icone: "syringe.fill",
            couleurIcone: Color(red: 0x7F / 255, green: 0x77 / 255, blue: 0xDD / 255),
            couleurFondIcone: Color(.secondarySystemGroupedBackground),
            titre: "Injection rapide",
            sousTitre: "il y a 5h40"
        ) {
            ValeurMetriqueAccueil(valeur: "14", unite: "u")
        }
        Divider().padding(.leading, 58)
        LigneMetriqueAccueil(
            icone: "fork.knife",
            couleurIcone: Color(red: 0x63 / 255, green: 0x99 / 255, blue: 0x22 / 255),
            couleurFondIcone: Color(.secondarySystemGroupedBackground),
            titre: "Repas",
            sousTitre: "2 aliments · il y a 5h40"
        ) {
            ValeurMetriqueAccueil(valeur: "148", unite: "g")
        }
    }
    .surfaceCarte()
    .padding()
    .background(Color(.systemGroupedBackground))
}
#endif
