//
//  SectionInsights.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Section « observations » de l'accueil — titre + pile verticale
/// des cartes d'insights produits par la couche ML. La carte active
/// est en bas (interactive, swipe vertical), les cartes suivantes
/// pointent au-dessus.
///
/// La section se masque entièrement quand le tableau est vide pour ne
/// pas laisser une coquille vide sur la page.
///
/// Position sur l'accueil : en tête de page, au-dessus de la section
/// « Aujourd'hui » (carte score + rappel lente).
struct SectionInsights: View {

    let insights: [Insight]

    /// Index de la carte actuellement au sommet de la pile. Bindé sur
    /// `PileVerticaleInsights` qui l'incrémente à chaque swipe validé.
    @State private var pageActive: Int = 0

    var body: some View {
        if !insights.isEmpty {
            // Spacing 0 entre le titre et la pile : le titre `.title2`
            // a déjà une grosse line-height qui crée une respiration
            // visuelle naturelle, on n'ajoute rien. La séparation
            // avec les sections voisines (carte score, « Aperçu du
            // jour ») est gérée par le VStack parent dans `AccueilVue`.
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Titre de section — compte d'observations
                // Style aligné sur « Aperçu du jour » dans `AccueilVue`
                // (title2.bold, .primary) pour homogénéiser les en-têtes
                // de section sur l'accueil.
                Text(libelleTendances)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)

                // MARK: Pile
                PileVerticaleInsights(insights: insights, indexActif: $pageActive)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Libellé du titre — accord singulier/pluriel français.
    /// Format : « Nouvelles tendances (4) » ou « Nouvelle tendance (1) ».
    private var libelleTendances: String {
        let pluriel = insights.count > 1 ? "s" : ""
        return "Nouvelle\(pluriel) tendance\(pluriel) (\(insights.count))"
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
