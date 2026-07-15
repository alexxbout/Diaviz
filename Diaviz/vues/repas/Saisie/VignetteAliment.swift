//
//  VignetteAliment.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import SwiftUI

/// Image d'un produit OFF chargée via `CacheImagesProduits` (cache mémoire +
/// disque, déduplication). Placeholder gris pendant le chargement,
/// pictogramme générique en cas d'échec.
struct ImageProduit: View {
    let url: URL
    var coinArrondi: CGFloat = 8

    @State private var image: UIImage?
    @State private var echec = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if echec {
                Image(systemName: "takeoutbag.and.cup.and.straw")
                    .foregroundStyle(.secondary)
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: coinArrondi))
        .task(id: url) {
            image = await CacheImagesProduits.shared.image(pour: url)
            echec = image == nil
        }
    }
}

/// Vignette unifiée d'un aliment : emoji (CIQUAL), photo (produit OFF) ou
/// pictogramme de fallback. Utilisée dans les listes de résultats, la bulle
/// du repas en cours et les rows du récapitulatif.
struct VignetteAliment: View {
    let aliment: ResultatRechercheAliment
    var taille: CGFloat = 36

    var body: some View {
        Group {
            if let emoji = aliment.emoji {
                Text(emoji)
                    .font(.system(size: taille * 0.75))
            } else if let url = aliment.imagePetiteURL {
                ImageProduit(url: url)
            } else {
                Image(systemName: "takeoutbag.and.cup.and.straw")
                    .font(.system(size: taille * 0.55))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: taille, height: taille)
    }
}
