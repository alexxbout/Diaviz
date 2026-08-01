//
//  PageTousRepasARevoir.swift
//  diaviz
//

import SwiftUI

/// Page « Tout voir » de la section accueil « Repas à revoir » — pushée
/// depuis le bouton du même nom (`SectionRepasARevoir`), visible dès qu'il y
/// a plus de repas que ce que l'accueil affiche.
///
/// Tous les repas en carte détaillée (`CarteRepasARevoir`), **aucune version
/// repliée** : contrairement à l'accueil (1 étendue + lignes compactes, place
/// limitée), cette page a l'espace pour tout montrer en grand.
struct PageTousRepasARevoir: View {

    let repas: [RepasARevoir]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(repas) { item in
                    CarteRepasARevoir(repas: item)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Repas à revoir")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Aperçus

#Preview {
    NavigationStack {
        PageTousRepasARevoir(repas: [.mockPadThai, .mockPizza, .mockBigMac, .mockSushi])
    }
}

#Preview("Vide") {
    NavigationStack {
        PageTousRepasARevoir(repas: [])
    }
}
