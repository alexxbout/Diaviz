//
//  CarteAliment.swift
//  diaviz
//
//  Created by Alexandre on 22/04/2026.
//

import SwiftUI

struct CarteAliment: View {
    let emoji: String
    let nom: String
    let quantite: Int
    let glucides: Int
    let insuline: Double
    /// Photo du produit (OFF) — prioritaire sur l'emoji quand présente.
    var imageURL: URL? = nil

    var body: some View {
        HStack {
            if let imageURL {
                ImageProduit(url: imageURL)
                    .frame(width: 40, height: 40)
            } else {
                Text(emoji)
                    .font(.largeTitle)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(nom)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(quantite)g")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(glucides)g")
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                Text(String(format: "%.1fu", insuline))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }
}

#Preview {
    VStack {
        CarteAliment(emoji: "🍚", nom: "Riz basmati", quantite: 60, glucides: 27, insuline: 2.0)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.secondarySystemBackground))
}

