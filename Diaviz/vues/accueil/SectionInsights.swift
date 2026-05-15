//
//  SectionInsights.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Section « observations » de l'accueil — titre + pile verticale
/// des cartes d'insights produits par la couche ML. La carte du
/// dessus est interactive (swipe vertical), les cartes derrière
/// pointent dessous. Un `IndicateurPages` custom placé à droite de
/// la pile, en colonne verticale, affiche la position courante en
/// adaptant ses couleurs au color scheme.
///
/// La section se masque entièrement quand le tableau est vide pour ne
/// pas laisser une coquille vide sur la page.
///
/// Position sur l'accueil : sous la carte score du jour, au-dessus
/// de la grille des 4 métriques.
struct SectionInsights: View {

    let insights: [Insight]

    /// Index de la carte actuellement au sommet de la pile. Bindé sur
    /// `PileVerticaleInsights` qui l'incrémente à chaque swipe validé.
    @State private var pageActive: Int = 0

    var body: some View {
        if !insights.isEmpty {
            // Spacing 4 (vs 8 par défaut) : le titre est déjà sur sa
            // ligne, on veut juste un petit air avant la première
            // carte, pas un saut entier.
            VStack(alignment: .leading, spacing: 4) {

                // MARK: Titre de section — compte d'observations
                // Style aligné sur « Aperçu du jour » dans `AccueilVue`
                // (title2.bold, .primary) pour homogénéiser les en-têtes
                // de section sur l'accueil.
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(libelleObservations)
                }
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .padding(.leading, 4)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                // MARK: Pile + indicateur vertical
                // HStack : cartes prennent la largeur restante, dots
                // alignés en colonne sur la droite et centrés
                // verticalement par rapport à la pile.
                // Padding bottom pour décoller la pile de la section
                // suivante (« Aperçu du jour ») qui sinon colle.
                HStack(alignment: .center, spacing: 12) {
                    PileVerticaleInsights(insights: insights, indexActif: $pageActive)
                        .frame(maxWidth: .infinity)

                    IndicateurPages(
                        nombre: insights.count,
                        actif: pageActive,
                        axe: .vertical
                    )
                }
                .padding(.bottom, 12)
            }
        }
    }

    /// Libellé du titre — accord singulier/pluriel français.
    private var libelleObservations: String {
        let suffixe = insights.count > 1 ? "s" : ""
        return "\(insights.count) observation\(suffixe)"
    }
}

// MARK: - Indicateur custom

/// Axe de rendu de l'indicateur de pages.
enum AxeIndicateur {
    case horizontal, vertical
}

/// Suite de dots, dot actif coloré en `Color.primary` (donc noir en
/// light mode et blanc en dark mode), dots inactifs en
/// `Color.secondary` semi-transparent — toujours lisibles quel que
/// soit le mode. Remplace les dots natifs du `UIPageControl` qui sont
/// blancs et invisibles sur fond clair. Peut s'afficher en ligne
/// (horizontal) ou en colonne (vertical) selon le contexte.
private struct IndicateurPages: View {

    let nombre: Int
    let actif: Int
    var axe: AxeIndicateur = .horizontal

    var body: some View {
        Group {
            switch axe {
            case .horizontal:
                HStack(spacing: 7) { dots }
                    .frame(maxWidth: .infinity)
            case .vertical:
                VStack(spacing: 7) { dots }
            }
        }
        .animation(.easeOut(duration: 0.18), value: actif)
        .accessibilityHidden(true)
    }

    /// Suite de cercles partagée par les deux orientations.
    @ViewBuilder
    private var dots: some View {
        ForEach(0..<nombre, id: \.self) { index in
            Circle()
                .fill(index == actif
                      ? Color.primary
                      : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Aperçus

#Preview("Insights - 4 observations") {
    ScrollView {
        SectionInsights(insights: InsightsAccueilServiceMock.mockComplet())
            .padding(.vertical, 16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Insights - 1 observation") {
    ScrollView {
        SectionInsights(insights: [.mockImpactSport])
            .padding(.vertical, 16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Insights - Aucun") {
    ScrollView {
        SectionInsights(insights: [])
            .padding(.vertical, 16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Insights - Sombre") {
    ScrollView {
        SectionInsights(insights: InsightsAccueilServiceMock.mockComplet())
            .padding(.vertical, 16)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
