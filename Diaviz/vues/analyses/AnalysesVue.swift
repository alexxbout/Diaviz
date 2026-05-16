//
//  AnalysesView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Page Analyses — **sommaire** des analyses disponibles. Chaque section
/// est une carte simple qui pousse une page dédiée via `NavigationLink`.
///
/// La page elle-même ne porte **aucun graphique** : c'est un index. Les
/// chiffres, courbes et tableaux vivent dans les pages de détail
/// (`DetailAnalyseBasaleVue`, etc.) pour que l'utilisateur puisse parcourir
/// d'un coup d'œil les verdicts sans charger 5 graphiques.
///
/// Header App Store style (titre + avatar) géré par `EnTetePage`, présent
/// à l'identique sur les quatre onglets racines.
struct AnalysesVue: View {

    /// Résumé alimentant la carte Basale. Mock par défaut le temps que la
    /// couche d'analyses ML produise les vrais verdicts ; injecté dans
    /// les previews pour exercer les 4 états visuels.
    let basale: AnalyseBasaleResume

    init(basale: AnalyseBasaleResume = .mockDefault) {
        self.basale = basale
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Analyses")

                ScrollView {
                    // Spacing 28pt entre sections — cohérent avec l'accueil,
                    // donne à chaque carte sommaire l'espace de respirer.
                    VStack(spacing: 28) {
                        CarteAnalyseBasale(resume: basale)
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Aperçus

#Preview("Analyses - Basale adaptée") {
    AnalysesVue(basale: .mockAdaptee)
        .environment(ProfilService.mockComplet())
}

#Preview("Analyses - Basale à revoir") {
    AnalysesVue(basale: .mockDefault)
        .environment(ProfilService.mockComplet())
}

#Preview("Analyses - Données insuffisantes") {
    AnalysesVue(basale: .mockDonneesInsuffisantes)
        .environment(ProfilService.mockComplet())
}
