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

    /// Résumé alimentant la carte « Analyse du coucher » (B1 + B2 + B3).
    /// Mock par défaut le temps que la couche d'analyses produise les vrais
    /// états ; injecté dans les previews pour exercer les états visuels.
    let coucher: ResumeAnalyseCoucher

    init(coucher: ResumeAnalyseCoucher = .mockDefault) {
        self.coucher = coucher
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Analyses")

                ScrollView {
                    // Spacing 28pt entre sections — cohérent avec l'accueil,
                    // donne à chaque carte sommaire l'espace de respirer.
                    VStack(spacing: 28) {
                        CarteAnalyseCoucher(resume: coucher)
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Aperçus

#Preview("Analyses - Coucher défaut") {
    AnalysesVue(coucher: .mockDefault)
        .environment(ProfilService.mockComplet())
}

#Preview("Analyses - Coucher mature") {
    AnalysesVue(coucher: .mockMature)
        .environment(ProfilService.mockComplet())
}

#Preview("Analyses - Coucher débutant") {
    AnalysesVue(coucher: .mockDebutant)
        .environment(ProfilService.mockComplet())
}
