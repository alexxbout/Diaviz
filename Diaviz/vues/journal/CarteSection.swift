//
//  CarteSection.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Carte de section plein hauteur, style **surface claire + accents
/// colorés** :
///
/// - **Fond** : surface neutre (`secondarySystemGroupedBackground`) +
///   ombre douce neutre → la carte se détache nettement du fond et lit
///   comme « tappable ».
/// - **Icône** : SF Symbol en couleur d'accent dans un disque
///   `couleur.opacity(0.18)`.
/// - **Texte** : titre en couleur d'accent (lisible sur surface claire),
///   sous-titre en `.secondary` neutre pour la hiérarchie.
/// - **Chevron** : `chevron.right` teinté à droite → affordance de nav.
///
/// Layout "héro éditorial" conservé : icône en haut à gauche, titre +
/// sous-titre en bas à gauche, chevron centré à droite, carte étirée
/// pour partager toute la hauteur disponible avec ses sœurs.
struct CarteSection: View {
    let icone: String
    let titre: String
    let sousTitre: String
    let couleur: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                iconeCirculaire

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(titre)
                        .font(.title.weight(.bold))
                        .foregroundStyle(couleur)

                    Text(sousTitre)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Chevron centré à droite — affordance de navigation, teinté
            // à l'accent (légèrement atténué pour rester sous le titre).
            Image(systemName: "chevron.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(couleur.opacity(0.7))
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Surface claire + ombre douce neutre : la carte se détache du
        // fond et reste très lisible ; l'accent reste porté par le titre,
        // l'icône et le chevron.
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre), \(sousTitre)")
        .accessibilityAddTraits(.isButton)
    }

    /// Disque coloré (accent à 18 %) contenant l'icône SF Symbol en
    /// couleur d'accent pleine. Diamètre 64 / icône 30 pour l'échelle
    /// carte hero.
    private var iconeCirculaire: some View {
        ZStack {
            Circle()
                .fill(couleur.opacity(0.18))
                .frame(width: 64, height: 64)

            Image(systemName: icone)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(couleur)
        }
        .accessibilityHidden(true)
    }

}

#Preview {
    VStack(spacing: 16) {
        CarteSection(
            icone: "fork.knife",
            titre: "Repas",
            sousTitre: "3 repas enregistrés aujourd'hui",
            couleur: .blue
        )
        CarteSection(
            icone: "figure.run",
            titre: "Activités sportives",
            sousTitre: "Aucune activité aujourd'hui",
            couleur: .orange
        )
        CarteSection(
            icone: "syringe",
            titre: "Médications",
            sousTitre: "Aucune médication aujourd'hui",
            couleur: .purple
        )
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
