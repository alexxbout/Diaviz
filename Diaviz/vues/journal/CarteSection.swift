//
//  CarteSection.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Carte de section plein hauteur, traitement aligné sur les cartes "warn"
/// de la `RepasSheet` (IOBCard, SportDetecteCard, ValidationRatioCard) :
///
/// - **Fond** : couleur d'accent unie à `0.10` d'opacité.
/// - **Icône** : SF Symbol en couleur pleine, encerclée par un disque
///   `couleur.opacity(0.18)`. L'icône reste lisible, le cercle donne du focus.
/// - **Texte** : titre et sous-titre directement dans la couleur d'accent
///   (titre solide, sous-titre à 70% pour la hiérarchie).
///
/// Layout "héro éditorial" conservé : icône en haut à gauche, titre + sous-titre
/// en bas à gauche, carte étirée pour partager toute la hauteur disponible
/// avec ses sœurs.
struct CarteSection: View {
    let icone: String
    let titre: String
    let sousTitre: String
    let couleur: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iconeCirculaire

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(titre)
                    .font(.title.weight(.bold))
                    .foregroundStyle(couleur)

                Text(sousTitre)
                    .font(.subheadline)
                    .foregroundStyle(couleur.opacity(0.70))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(couleur.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre), \(sousTitre)")
    }

    /// Disque coloré contenant l'icône SF Symbol en couleur pleine.
    /// Le rapport diamètre cercle / taille icône (~64/30) reproduit celui
    /// des cartes warn (~40/22) à plus grande échelle pour la carte hero.
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
