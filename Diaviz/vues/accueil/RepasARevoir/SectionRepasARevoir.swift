//
//  SectionRepasARevoir.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Section « Repas à revoir » — affichée sur l'accueil sous la
/// section des insights. Liste en scroll horizontal les repas dont
/// la dernière occurrence est sortie de cible et qui contiennent au
/// moins un aliment estimé (flag glucides incertains), hors fenêtre
/// de sport.
///
/// Auto-masquée si le tableau est vide : pas de coquille vide entre
/// les insights et le bloc « Aperçu du jour ».
///
/// Le scroll horizontal sort du padding 16pt du parent : le titre
/// reste aligné sur les autres en-têtes de section, mais le ScrollView
/// va d'edge à edge pour donner sa pleine largeur au défilement (la
/// première carte commence à 16pt du bord gauche).
struct SectionRepasARevoir: View {

    let repas: [RepasARevoir]

    var body: some View {
        if !repas.isEmpty {
            VStack(alignment: .leading, spacing: 12) {

                // MARK: En-tête de section
                // Titre `.title2.bold()` + compteur entre parenthèses
                // — même graphisme que les autres en-têtes de
                // l'accueil (« Aperçu du jour », « Nouvelles tendances »).
                // `.padding(.leading, 4)` aligne le titre sur ces
                // mêmes en-têtes.
                Text("Repas à revoir (\(repas.count))")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)

                // MARK: Scroll horizontal
                // Padding latéral 16pt à l'intérieur du LazyHStack pour
                // que la première et la dernière carte aient le même
                // air que les bords de la liste. Le LazyHStack diffère
                // le rendu des cartes hors-écran (utile dès qu'on aura
                // plus que 3 mocks).
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(repas) { item in
                            CarteRepasARevoir(repas: item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                // Marges négatives pour annuler le padding 16pt que le
                // parent `AccueilVue` applique au VStack — le scroll
                // doit déborder edge-to-edge, pas le titre.
                .padding(.horizontal, -16)
            }
        }
    }
}

// MARK: - Aperçus

#Preview("Repas à revoir - 3 repas") {
    ScrollView {
        SectionRepasARevoir(repas: RepasAReevoirServiceMock.mock())
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Repas à revoir - Vide") {
    ScrollView {
        SectionRepasARevoir(repas: [])
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Repas à revoir - Sombre") {
    ScrollView {
        SectionRepasARevoir(repas: RepasAReevoirServiceMock.mock())
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
