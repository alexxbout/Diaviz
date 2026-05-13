//
//  AccueilVue.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Page d'accueil — carte score quotidien (résumé de la veille) et
/// futures cartes d'analyses.
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
                        // Carte score quotidien — données mockées en
                        // attendant la couche d'analyses.
                        CarteScoreQuotidien(
                            contenu: ContenuCarteScore(
                                score: 82,
                                date: hier,
                                historique: [65, 78, 71, 55, 88, 73, 82]
                            ),
                            style: .gradient,
                            onTap: { sheetScoreOuverte = true }
                        )
                    }
                    .padding(16)
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
