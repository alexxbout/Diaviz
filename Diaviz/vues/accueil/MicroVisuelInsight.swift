//
//  MicroVisuelInsight.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Rendu de la **donnée clé** d'une carte d'observation — c'est
/// l'élément dominant visuel de la carte, centré horizontalement et
/// dimensionné autour de 40pt pour ancrer la hiérarchie.
///
/// Toujours rendu dans une frame `maxWidth: .infinity` pour permettre
/// le centrage horizontal quel que soit l'alignement du `VStack`
/// parent (typiquement `.leading` dans `CarteInsight`).
///
/// Le rendu est piloté par `MicroVisuelType` ; ajouter une variante
/// consiste à étendre l'enum + une branche du switch ici.
struct MicroVisuelInsight: View {

    let type: MicroVisuelType
    /// Couleur d'accent — héritée de la catégorie de la carte parente,
    /// appliquée à la donnée clé (chiffre, flèche, barres, icône).
    let couleur: Color

    var body: some View {
        Group {
            switch type {

            // MARK: Grand chiffre seul — ex : « -25% »
            case .grandNombre(let valeur):
                Text(valeur)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(couleur)
                    .monospacedDigit()
                    .accessibilityLabel(valeur)

            // MARK: Grand chiffre + flèche directionnelle — ex : « 3 nuits ↘ »
            case .grandNombreAvecFleche(let valeur, let direction):
                HStack(spacing: 8) {
                    Text(valeur)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(couleur)
                        .monospacedDigit()
                    Image(systemName: direction)
                        .font(.title)
                        .foregroundStyle(couleur)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(valeur), tendance")

            // MARK: Mini bar chart — 4 barres 12pt × hauteur, ligne seuil
            // grise à mi-hauteur du conteneur 40pt.
            case .barres(let hauteurs):
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(hauteurs.enumerated()), id: \.offset) { _, h in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(couleur)
                            .frame(width: 12, height: h)
                    }
                }
                .frame(height: 40)
                .overlay(alignment: .bottom) {
                    // Trait fin gris symbolisant le seuil ~200 mg/dL,
                    // placé à mi-hauteur du conteneur (20pt du bas).
                    // Les barres > 20pt le dépassent visuellement.
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(height: 0.5)
                        .offset(y: -20)
                }
                .accessibilityElement()
                .accessibilityLabel("\(hauteurs.count) repas, plusieurs ont dépassé le seuil")

            // MARK: Grande icône SF Symbol — ex : `figure.run`
            case .grandeIcone(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: 36))
                    .foregroundStyle(couleur)
                    .accessibilityHidden(true)
            }
        }
        // Centrage horizontal de la donnée clé dans la carte — le
        // VStack parent est `.leading`, on étire ici pour permettre
        // au contenu de se centrer.
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Aperçus

#Preview("Grand nombre — bleu") {
    MicroVisuelInsight(
        type: .grandNombre(valeur: "-25%"),
        couleur: .blue
    )
    .padding()
}

#Preview("Nombre + flèche — orange") {
    MicroVisuelInsight(
        type: .grandNombreAvecFleche(valeur: "3 nuits", direction: "arrow.down.right"),
        couleur: .orange
    )
    .padding()
}

#Preview("Mini barres — orange") {
    MicroVisuelInsight(
        type: .barres(hauteurs: [20, 28, 35, 24]),
        couleur: .orange
    )
    .padding()
}

#Preview("Grande icône — violet") {
    MicroVisuelInsight(
        type: .grandeIcone(systemName: "figure.run"),
        couleur: .purple
    )
    .padding()
}
