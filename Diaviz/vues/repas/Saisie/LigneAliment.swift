//
//  LigneAliment.swift
//  diaviz
//
//  Created by Alexandre on 27/04/2026.
//

import SwiftUI

// Ligne d'un aliment dans la liste — utilisée à la fois pour les récents et
// les résultats de recherche, toutes sources confondues (CIQUAL / OFF).
// .buttonStyle(.plain) empêche SwiftUI d'appliquer la teinte bleue du Button sur le contenu.
struct LigneAliment: View {
    let aliment: ResultatRechercheAliment

    var body: some View {
        Button {
            // Enregistre l'aliment comme récemment utilisé (MRU, persisté dans UserDefaults)
            AlimentsRecentsService.shared.marquerUtilise(aliment)
            // TODO: ajouter au repas en cours
        } label: {
            HStack(spacing: 12) {
                VignetteAliment(aliment: aliment, taille: 36)
                VStack(alignment: .leading) {
                    if AlimentsRecentsService.shared.estRecent(aliment) {
                        Text("Récemment ajouté")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                    Text(aliment.nom)
                        .font(.body)
                    if let marque = aliment.marque {
                        Text(marque)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if aliment.glucidesRenseignes {
                        Text("\(Int(aliment.glucides))g glucides / 100g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Glucides non renseignés")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let pomme = AlimentCiqual(id: 1, nom: "Pomme, pulpe et peau, crue", calories: 52, glucides: 12.6, sucres: 10.4, proteines: 0.3, lipides: 0.2, fibres: 2.4, emoji: "🍎")
    let nutella = AlimentOFF(code: "3017620422003", nom: "Nutella", marque: "Ferrero", calories: 539, glucides: 57.5, sucres: 56.3, proteines: 6.3, lipides: 30.9, fibres: nil, imagePetiteURL: nil, imageURL: nil)
    let mystere = AlimentOFF(code: "123", nom: "Produit sans nutriments", marque: nil, calories: nil, glucides: nil, sucres: nil, proteines: nil, lipides: nil, fibres: nil, imagePetiteURL: nil, imageURL: nil)

    List {
        LigneAliment(aliment: .ciqual(pomme))
        LigneAliment(aliment: .off(nutella))
        LigneAliment(aliment: .off(mystere))
    }
}
