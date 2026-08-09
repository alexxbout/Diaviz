//
//  RangeeBadges.swift
//  diaviz
//

import SwiftUI

/// Un badge factuel : libellé court, couleur porteuse de sens, icône
/// optionnelle. Volontairement sans logique — c'est l'appelant qui décide de
/// la couleur, donc de la catégorie (bleu sport, violet ajustement, orange
/// contexte…), comme le faisait déjà `CarteRepasARevoir`.
struct ItemBadge: Identifiable {
    let id = UUID()
    let libelle: String
    let couleur: Color
    var systemImage: String?

    init(_ libelle: String, couleur: Color, systemImage: String? = nil) {
        self.libelle = libelle
        self.couleur = couleur
        self.systemImage = systemImage
    }
}

/// Rangée de badges capsule qui **passe à la ligne** quand elle déborde.
///
/// Un simple `HStack` tronquait le dernier badge dès qu'un repas cumulait
/// deux ajustements et un contexte — or un badge à moitié coupé ne se lit
/// pas, autant le renvoyer à la ligne. D'où le `Layout` custom : `WrappingHStack`
/// n'existe pas en SwiftUI, et un `LazyVGrid` imposerait des colonnes de
/// largeur fixe alors que ces badges ont des largeurs très variables.
struct RangeeBadges: View {
    let items: [ItemBadge]

    var body: some View {
        if !items.isEmpty {
            FlotBadges(espacement: 6, espacementLignes: 6) {
                ForEach(items) { item in
                    badge(item)
                }
            }
        }
    }

    private func badge(_ item: ItemBadge) -> some View {
        HStack(spacing: 3) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(item.libelle)
        }
        .font(.caption)
        .foregroundStyle(item.couleur)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(item.couleur.opacity(0.15), in: Capsule())
    }
}

// MARK: - Layout

/// Layout en flot : place les sous-vues de gauche à droite, passe à la ligne
/// quand la largeur proposée est dépassée.
private struct FlotBadges: Layout {
    var espacement: CGFloat
    var espacementLignes: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeurMax = proposal.width ?? .infinity
        let lignes = decouperEnLignes(subviews: subviews, largeurMax: largeurMax)

        let hauteur = lignes.reduce(into: CGFloat.zero) { total, ligne in
            let hauteurLigne = ligne.map(\.hauteur).max() ?? 0
            total += hauteurLigne
        } + CGFloat(max(0, lignes.count - 1)) * espacementLignes

        let largeur = lignes.map { ligne in
            ligne.reduce(0) { $0 + $1.largeur } + CGFloat(max(0, ligne.count - 1)) * espacement
        }.max() ?? 0

        return CGSize(width: min(largeur, largeurMax), height: hauteur)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lignes = decouperEnLignes(subviews: subviews, largeurMax: bounds.width)
        var y = bounds.minY

        for ligne in lignes {
            var x = bounds.minX
            let hauteurLigne = ligne.map(\.hauteur).max() ?? 0
            for element in ligne {
                subviews[element.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: element.largeur, height: element.hauteur)
                )
                x += element.largeur + espacement
            }
            y += hauteurLigne + espacementLignes
        }
    }

    private struct Element {
        let index: Int
        let largeur: CGFloat
        let hauteur: CGFloat
    }

    private func decouperEnLignes(subviews: Subviews, largeurMax: CGFloat) -> [[Element]] {
        var lignes: [[Element]] = []
        var ligneCourante: [Element] = []
        var largeurCourante: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let taille = subview.sizeThatFits(.unspecified)
            let largeurAjoutee = ligneCourante.isEmpty ? taille.width : taille.width + espacement

            if !ligneCourante.isEmpty && largeurCourante + largeurAjoutee > largeurMax {
                lignes.append(ligneCourante)
                ligneCourante = []
                largeurCourante = 0
                ligneCourante.append(Element(index: index, largeur: taille.width, hauteur: taille.height))
                largeurCourante = taille.width
            } else {
                ligneCourante.append(Element(index: index, largeur: taille.width, hauteur: taille.height))
                largeurCourante += largeurAjoutee
            }
        }

        if !ligneCourante.isEmpty { lignes.append(ligneCourante) }
        return lignes
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Rangée simple") {
    RangeeBadges(items: [
        ItemBadge("Sport récent · Course à pied", couleur: .blue, systemImage: "figure.run"),
        ItemBadge("Je prends la voiture", couleur: .purple, systemImage: "text.bubble"),
    ])
    .padding()
}

#Preview("Débordement sur deux lignes") {
    RangeeBadges(items: [
        ItemBadge("Sport récent · Course à pied", couleur: .blue, systemImage: "figure.run"),
        ItemBadge("Glycémie basse avant repas", couleur: .purple),
        ItemBadge("Repas riche en graisse", couleur: .purple),
        ItemBadge("Je prends la voiture", couleur: .orange, systemImage: "text.bubble"),
    ])
    .padding()
}
#endif
