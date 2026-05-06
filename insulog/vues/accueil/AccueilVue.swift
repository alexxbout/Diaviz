//
//  AccueilVue.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Page d'accueil — pour l'instant une carte unique « score quotidien »
/// au-dessus de l'espace réservé pour les futurs blocs.
///
/// Header App Store style (titre + avatar sur la même ligne) géré par
/// le composant partagé `EnTetePage`, présent à l'identique sur
/// les quatre onglets racines.
struct AccueilVue: View {

    @State private var sheetScoreOuverte = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Accueil")

                ScrollView {
                    VStack(spacing: 16) {
                        // Données mockées : la couche d'analyses GRI
                        // n'est pas encore branchée (cf. CLAUDE.md).
                        CarteScoreQuotidien(
                            score: 82,
                            date: hier,
                            historique: [65, 78, 71, 55, 88, 73, 82],
                            onTap: { sheetScoreOuverte = true }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $sheetScoreOuverte) {
                detailsScorePlaceholder
            }
        }
    }

    private var hier: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    private var detailsScorePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Détails du score")
                .font(.headline)
            Text("Implémentation à venir.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .presentationDetents([.medium])
    }
}

#Preview("Avec profil complet") {
    AccueilVue()
        .environment(ProfilService.mockComplet())
}

#Preview("Profil neuf") {
    AccueilVue()
        .environment(ProfilService.mockVide())
}
