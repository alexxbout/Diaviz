//
//  GrilleMetriquesAccueil.swift
//  diaviz
//

import SwiftUI

/// Liste compacte des 4 métriques d'accueil ("Aperçu du jour"), une colonne,
/// style réglages iOS — remplace l'ancienne grille 2×2 dont les cartes
/// (Insuline active, Injection, Repas) laissaient un grand vide sous leur
/// valeur, et mêlaient emoji et SF Symbols au sein de la même grille.
///
/// Une seule surface (`secondarySystemGroupedBackground`, coin 16pt)
/// enveloppe les 4 rows séparées par des `Divider`. La row Hypos est la
/// seule à dépasser la hauteur d'une ligne simple : elle garde son en-tête
/// compact et déplie un mini-graphe glycémique pleine largeur en dessous.
struct GrilleMetriquesAccueil: View {

    let metriques: MetriquesAccueil

    /// IOB **réel** (calculé depuis le hub), fourni à part du snapshot mock le
    /// temps que les 3 autres cartes passent aussi au réel.
    let iobValeur: Double
    let iobPoints: [PointIOB]

    var body: some View {
        VStack(spacing: 0) {
            CarteHypos(
                count: metriques.hyposAujourdhui,
                severes: metriques.hyposSeveres,
                legeres: metriques.hyposLegeres,
                pointsCgm: metriques.pointsCgmJournee
            )

            Divider().padding(.leading, 58)

            CarteIOB(valeur: iobValeur, pointsIOB: iobPoints)

            Divider().padding(.leading, 58)

            CarteDerniereInjection(derniere: metriques.derniereInjection)

            Divider().padding(.leading, 58)

            CarteDernierRepas(dernier: metriques.dernierRepas)
        }
        .surfaceCarte()
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Liste - Normal") {
    ScrollView {
        GrilleMetriquesAccueil(metriques: .mockNormal, iobValeur: MetriquesAccueil.mockNormal.iob, iobPoints: MetriquesAccueil.mockNormal.pointsIOB)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Liste - Alerte") {
    ScrollView {
        GrilleMetriquesAccueil(metriques: .mockAlerte, iobValeur: MetriquesAccueil.mockAlerte.iob, iobPoints: MetriquesAccueil.mockAlerte.pointsIOB)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Liste - Calme") {
    ScrollView {
        GrilleMetriquesAccueil(metriques: .mockCalme, iobValeur: MetriquesAccueil.mockCalme.iob, iobPoints: MetriquesAccueil.mockCalme.pointsIOB)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Liste - Sombre") {
    ScrollView {
        GrilleMetriquesAccueil(metriques: .mockNormal, iobValeur: MetriquesAccueil.mockNormal.iob, iobPoints: MetriquesAccueil.mockNormal.pointsIOB)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
#endif
