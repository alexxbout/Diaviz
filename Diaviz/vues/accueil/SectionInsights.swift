//
//  SectionInsights.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Section « observations » de l'accueil — titre + TabView paginé
/// avec les cartes d'insights produits par la couche ML. Les dots
/// natifs du `.page` TabView sont désactivés au profit d'un
/// `IndicateurPages` custom rendu juste en dessous, qui adapte ses
/// couleurs au color scheme (`Color.primary` pour l'actif,
/// `Color.secondary.opacity(...)` pour les inactifs) — sinon le
/// `UIPageControl` natif rend les dots en blanc translucide,
/// illisibles sur fond clair.
///
/// La section se masque entièrement quand le tableau est vide pour ne
/// pas laisser une coquille vide sur la page.
///
/// Position sur l'accueil : sous la carte score du jour, au-dessus
/// de la grille des 4 métriques.
struct SectionInsights: View {

    let insights: [Insight]

    /// Index de la carte actuellement visible. Bindé sur le `TabView`
    /// pour piloter l'indicateur custom et suivre les swipes user.
    @State private var pageActive: Int = 0

    /// Hauteur fixe du TabView — réservée aux cartes uniquement (les
    /// indicateurs sont externes maintenant). Calé pour qu'un message
    /// de 2 lignes tienne même avec un micro-visuel de 30pt.
    private let hauteurTabView: CGFloat = 180

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {

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

                // MARK: TabView paginé — dots natifs OFF, swipe ON
                // Padding horizontal léger (8pt par côté) pour créer
                // un écart visible entre cartes pendant le swipe ;
                // sinon, les cartes adjacentes paraissent collées.
                // Reste fin pour que la carte ne soit pas sensiblement
                // plus étroite que la carte score du dessus.
                TabView(selection: $pageActive) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        CarteInsight(insight: insight)
                            .padding(.horizontal, 8)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: hauteurTabView)

                // MARK: Indicateur de pages custom — color scheme aware
                IndicateurPages(nombre: insights.count, actif: pageActive)
                    .padding(.top, 4)
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

/// Suite de dots centrés horizontalement, dot actif coloré en
/// `Color.primary` (donc noir en light mode et blanc en dark mode),
/// dots inactifs en `Color.secondary` semi-transparent — toujours
/// lisibles quel que soit le mode. Remplace les dots natifs du
/// `UIPageControl` qui sont blancs et invisibles sur fond clair.
private struct IndicateurPages: View {

    let nombre: Int
    let actif: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<nombre, id: \.self) { index in
                Circle()
                    .fill(index == actif
                          ? Color.primary
                          : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: actif)
        .accessibilityHidden(true)
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
