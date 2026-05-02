//
//  LigneAliment.swift
//  insulog
//
//  Created by Alexandre on 27/04/2026.
//

import SwiftUI

// Ligne d'un aliment dans la liste — utilisée à la fois pour les récents et les résultats de recherche.
// .buttonStyle(.plain) empêche SwiftUI d'appliquer la teinte bleue du Button sur le contenu.
struct LigneAliment: View {
    let aliment: AlimentCiqual

    var body: some View {
        Button {
            // Enregistre l'aliment comme récemment utilisé (MRU, persisté dans UserDefaults)
            AlimentsRecentsService.shared.marquerUtilise(aliment)
            // TODO: ajouter au repas en cours
        } label: {
            HStack(spacing: 12) {
                if let emoji = aliment.emoji {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: 36, height: 36)
                }
                VStack(alignment: .leading) {
                    if AlimentsRecentsService.shared.estRecent(aliment) {
                        Text("Récemment ajouté")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                    Text(aliment.nom)
                        .font(.body)
                    Text("\(Int(aliment.glucides))g glucides / 100g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let pomme = AlimentCiqual(id: 1, nom: "Pomme, pulpe et peau, crue", calories: 52, glucides: 12.6, sucres: 10.4, proteines: 0.3, lipides: 0.2, fibres: 2.4, emoji: "🍎")
    let pain  = AlimentCiqual(id: 2, nom: "Pain complet aux graines de tournesol et de lin", calories: 247, glucides: 45, sucres: 3, proteines: 9, lipides: 3, fibres: 6, emoji: "🍞")

    List {
        LigneAliment(aliment: pomme)
        LigneAliment(aliment: pain)
    }
}
