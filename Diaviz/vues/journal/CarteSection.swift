//
//  CarteSection.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Carte de section compacte, fond opaque teinté à l'accent de la section :
///
/// - **Fond** : `surfaceCarte(fond:)`, teinte `couleur.opacity(0.10)` — le
///   Liquid Glass d'origine a été retiré (carte de contenu, pas un élément
///   de navigation flottant — voir skill `liquid-glass` : le verre est
///   réservé aux barres/toolbars/sheets, pas aux cartes de données).
/// - **Icône** : badge circulaire plein `couleur.gradient`, SF Symbol blanc.
/// - **Texte** : titre en couleur d'accent, sous-titre en `.secondary`.
/// - **Chevron** : `chevron.right` teinté à droite → affordance de nav.
///
/// Layout **horizontal compact** : icône à gauche, titre + sous-titre au
/// centre, chevron à droite. Hauteur intrinsèque (plus de `maxHeight:
/// .infinity` qui étirait la carte et laissait un grand vide au milieu).
struct CarteSection: View {
    let icone: String
    let titre: String
    let sousTitre: String
    let couleur: Color

    /// Nombre d'éléments en attente d'import (ex. activités Apple Santé) —
    /// `nil`/0 masque la pastille. Remplace aussi le sous-titre normal par
    /// un message dédié, pour qu'il n'y ait qu'une seule information « à
    /// traiter » affichée à la fois, jamais un badge en overlay par-dessus
    /// le titre qui se chevauchaient.
    var badgeImport: Int? = nil

    private var teinteFond: Color { couleur.opacity(0.10) }

    private var sousTitreEffectif: String {
        guard let badgeImport, badgeImport > 0 else { return sousTitre }
        return "\(badgeImport) activité\(badgeImport > 1 ? "s" : "") à importer"
    }

    var body: some View {
        HStack(spacing: 16) {
            iconeBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(titre)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(couleur)

                Text(sousTitreEffectif)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(couleur.opacity(0.55))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        // `minHeight` fixe : le sous-titre peut faire 1 ou 2 lignes selon le
        // compteur du jour (« Aucune activité » vs « 3 médications
        // enregistrées aujourd'hui ») — sans plancher commun les trois
        // cartes n'avaient pas la même hauteur.
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        // Fond opaque teinté à l'accent de la section (plus de Liquid Glass —
        // voir commentaire en tête de fichier). L'ombre colorée vit hors de
        // cette vue, posée par l'appelant sur le `NavigationLink` — voir
        // `JournalVue` : appliquée ici, dans le `label:` du lien, elle se
        // faisait rogner par le système de rendu du bouton et ne
        // s'affichait jamais.
        .surfaceCarte(fond: teinteFond)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre), \(sousTitreEffectif)")
        .accessibilityAddTraits(.isButton)
    }

    /// Badge circulaire plein (dégradé de l'accent) avec l'icône SF Symbol
    /// blanche — contraste franc sur le verre teinté de la carte. Porte la
    /// pastille « à importer » en overlay, jamais sur la carte entière : sa
    /// zone est fixe (54pt) quel que soit le nombre affiché, contrairement
    /// au titre qui peut changer de largeur.
    private var iconeBadge: some View {
        Image(systemName: icone)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(couleur.gradient, in: Circle())
            .overlay(alignment: .topTrailing) { pastilleImport }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var pastilleImport: some View {
        if let badgeImport, badgeImport > 0 {
            Text("\(badgeImport)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(minWidth: 19, minHeight: 19)
                .background(Color.red, in: Circle())
                .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

#if DEBUG
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
            couleur: .orange,
            badgeImport: 1
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
#endif
