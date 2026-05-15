//
//  GrilleMetriquesAccueil.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import SwiftUI

// MARK: - Coquille partagée

/// Conteneur visuel commun aux 4 cartes de la grille d'accueil :
/// fond `secondarySystemGroupedBackground` uniforme, corner radius
/// 16pt, padding interne 16pt. Pas de bordure, **pas de shadow** —
/// la différenciation des cartes passe **uniquement** par leurs
/// couleurs d'accents internes (titre, valeur, badge, points du
/// chart). Cohérent avec le reste de l'app, où seule la carte score
/// (avec son mesh gradient) porte un relief visuel.
///
/// Factorise les invariants graphiques pour qu'un changement (corner
/// radius, padding) se propage automatiquement aux 4 cartes.
struct CarteMetriqueShell<Content: View>: View {

    /// Contenu interne de la carte, composé par la carte appelante.
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}

// MARK: - Grille

/// Grille 2×2 des 4 cartes métriques d'accueil. Spacing 10pt entre
/// cartes, padding latéral 16pt géré par l'appelant (`AccueilVue`).
///
/// Les cartes sont rendues via une LazyVGrid à 2 colonnes flexibles,
/// ce qui les fait s'étirer à la largeur d'écran tout en restant
/// alignées. La hauteur minimale (`minCarteHauteur`) garantit un
/// rendu cohérent même quand le contenu d'une carte est plus court.
struct GrilleMetriquesAccueil: View {

    let metriques: MetriquesAccueil

    /// Hauteur minimale d'une carte — ~180pt, calée pour accommoder
    /// les mini-courbes (24pt) ajoutées en bas des cartes Hypos et
    /// IOB sans écraser les libellés. Les cartes Injection et Repas
    /// sans graphique s'alignent à la même hauteur grâce au Spacer
    /// interne de la coquille, qui absorbe la différence.
    private let minCarteHauteur: CGFloat = 180

    /// Deux colonnes flexibles avec 10pt entre elles — la LazyVGrid
    /// répartit la largeur restante équitablement.
    private let colonnes: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: colonnes, spacing: 10) {

            // MARK: Haut-gauche — hypos du jour
            CarteHypos(
                count: metriques.hyposAujourdhui,
                severes: metriques.hyposSeveres,
                legeres: metriques.hyposLegeres,
                pointsCgm: metriques.pointsCgmJournee
            )
            .frame(minHeight: minCarteHauteur)

            // MARK: Haut-droite — insuline active
            CarteIOB(
                valeur: metriques.iob,
                pointsIOB: metriques.pointsIOB
            )
            .frame(minHeight: minCarteHauteur)

            // MARK: Bas-gauche — dernière injection
            CarteDerniereInjection(
                dose: metriques.derniereInjectionDose,
                depuis: metriques.derniereInjectionDepuis,
                type: metriques.derniereInjectionType
            )
            .frame(minHeight: minCarteHauteur)

            // MARK: Bas-droite — dernier repas
            CarteDernierRepas(
                glucides: metriques.dernierRepasGlucides,
                depuis: metriques.dernierRepasDepuis,
                emojis: metriques.dernierRepasEmojis
            )
            .frame(minHeight: minCarteHauteur)
        }
    }
}

// MARK: - Aperçus

#Preview("Grille - Normal") {
    ScrollView {
        GrilleMetriquesAccueil(metriques: .mockNormal)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Grille - Alerte") {
    ScrollView {
        GrilleMetriquesAccueil(metriques: .mockAlerte)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Grille - Calme") {
    ScrollView {
        GrilleMetriquesAccueil(metriques: .mockCalme)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Grille - Sombre") {
    ScrollView {
        GrilleMetriquesAccueil(metriques: .mockNormal)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
