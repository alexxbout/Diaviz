//
//  DetailAnalyseBasaleVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Page dédiée de l'analyse basale — poussée depuis la carte sommaire
/// `CarteAnalyseBasale` sur la page Analyses.
///
/// Volontairement vide pour le moment : seule la chrome de navigation
/// (titre `.inline`) est posée, ce qui permet de câbler le push complet
/// (carte → page) avant que la couche d'analyses ne produise les
/// chiffres détaillés (heures de divergence, graphiques par tranche
/// horaire, recommandations d'ajustement).
struct DetailAnalyseBasaleVue: View {

    var body: some View {
        ScrollView {
            ContentUnavailableView(
                "Analyse à venir",
                systemImage: "syringe.fill",
                description: Text("Le détail par tranche horaire et l'historique des ajustements seront affichés ici.")
            )
            .padding(.top, 64)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Analyse basale")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DetailAnalyseBasaleVue()
    }
}
