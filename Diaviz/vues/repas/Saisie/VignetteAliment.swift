//
//  VignetteAliment.swift
//  diaviz
//

import SwiftUI

/// Image d'un produit OFF chargée via `CacheImagesProduits` (cache mémoire +
/// disque, déduplication). Placeholder gris pendant le chargement,
/// pictogramme générique en cas d'échec.
///
/// **Carré garanti** via `GeometryReader` : l'image est explicitement
/// dimensionnée à la taille proposée (`geo.size`) avant `.clipped()`, plutôt
/// que de compter sur la simple propagation de la proposition de taille —
/// dans une row de `List`/`Form`, cette propagation ne bornait pas toujours
/// le rendu réel de l'image (les photos très hautes/portrait débordaient du
/// carré malgré un `.frame()` posé par l'appelant).
struct ImageProduit: View {
    let url: URL
    var coinArrondi: CGFloat = 8

    /// `true` (défaut) : remplit le frame donné par l'appelant en recadrant
    /// (`fill` + clip) — carré partout (listes, bulle). `false` : préserve
    /// l'aspect naturel sans découpe (`fit`) — utilisé uniquement par le hero
    /// de `DetailAlimentSheet`.
    var remplir: Bool = true

    @State private var image: UIImage?
    @State private var echec = false

    var body: some View {
        Group {
            if remplir {
                // Mode carré (listes, bulle) : `GeometryReader` force
                // explicitement l'image à la taille réellement proposée avant
                // `.clipped()` — dans une row de `List`/`Form`, compter sur la
                // simple propagation de la proposition de taille ne suffisait
                // pas (les photos très hautes/portrait débordaient du carré).
                GeometryReader { geo in
                    contenu
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                // Mode ajuster (hero `DetailAlimentSheet`) : pas de carré
                // forcé, l'image garde sa taille naturelle dans les bornes
                // maxWidth/maxHeight posées par l'appelant — inchangé par
                // rapport au comportement d'origine.
                contenu
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: coinArrondi, style: .continuous))
        .task(id: url) {
            image = await CacheImagesProduits.shared.image(pour: url)
            echec = image == nil
        }
    }

    @ViewBuilder
    private var contenu: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: remplir ? .fill : .fit)
        } else if echec {
            Image(systemName: "takeoutbag.and.cup.and.straw")
                .foregroundStyle(.secondary)
        } else {
            Color(.tertiarySystemFill)
        }
    }
}

/// Vignette unifiée d'un aliment : emoji (CIQUAL), photo (produit OFF) ou
/// pictogramme de fallback. Utilisée dans les listes de résultats, la bulle
/// du repas en cours et les rows du récapitulatif — **seul point d'entrée**
/// pour afficher un aliment en vignette carrée, pour ne pas dupliquer la
/// logique de carré garanti à chaque appelant.
struct VignetteAliment: View {
    let aliment: ResultatRechercheAliment
    var taille: CGFloat = 36
    var coinArrondi: CGFloat = 8
    /// Proportion de `taille` occupée par l'emoji — réduite dans la grille
    /// (vignettes larges) où l'emoji plein cadre paraissait disproportionné.
    var echelleEmoji: CGFloat = 0.75

    var body: some View {
        Group {
            if let emoji = aliment.emoji {
                Text(emoji)
                    .font(.system(size: taille * echelleEmoji))
                    .frame(width: taille, height: taille)
            } else if let url = aliment.imagePetiteURL {
                ImageProduit(url: url, coinArrondi: coinArrondi)
                    .frame(width: taille, height: taille)
            } else {
                Image(systemName: "takeoutbag.and.cup.and.straw")
                    .font(.system(size: taille * 0.55))
                    .foregroundStyle(.secondary)
                    .frame(width: taille, height: taille)
            }
        }
        // Filet de sécurité : même si une branche ci-dessus oubliait son
        // propre `.frame`, celui-ci force le carré final.
        .frame(width: taille, height: taille)
    }
}
