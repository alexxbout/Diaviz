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

    /// Appelé quand l'utilisateur demande la suppression d'un insight (swipe
    /// gauche ou appui long sur la carte active) — le parent affiche la
    /// confirmation, cette vue ne supprime jamais directement.
    var onDemandeSuppression: ((Insight) -> Void)? = nil

    /// Appelé sur tap simple de la carte active — thread vers `PileVerticaleInsights`.
    var onTap: ((Insight) -> Void)? = nil

    /// Index de la carte actuellement au sommet de la pile. Bindé sur
    /// `PileVerticaleInsights` qui l'incrémente à chaque swipe validé.
    @State private var pageActive: Int = 0

    var body: some View {
        if !insights.isEmpty {
            // Spacing 18 entre le titre et la pile pour aérer sous
            // l'en-tête. Le `.padding(.bottom, -14)` resserre ensuite la
            // section sur la suivante (« Aujourd'hui ») en annulant une
            // partie du spacing 28 du VStack parent dans `AccueilVue`,
            // sans toucher aux autres inter-sections. Géré ici (et pas
            // sur l'appel dans `AccueilVue`) pour disparaître avec la
            // section quand elle est masquée (tableau vide).
            VStack(alignment: .leading, spacing: 18) {

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
                PileVerticaleInsights(
                    insights: insights,
                    indexActif: $pageActive,
                    onDemandeSuppression: onDemandeSuppression,
                    onTap: onTap
                )
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, -14)
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

#if DEBUG
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
#endif
