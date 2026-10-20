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

            // MARK: Icône + conclusion en toutes lettres — ex : « ✓ Stable »
            case .iconeEtTexte(let systemName, let texte):
                HStack(spacing: 10) {
                    Image(systemName: systemName)
                        .font(.system(size: 30))
                        .accessibilityHidden(true)
                    Text(texte)
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(couleur)

            // MARK: Grand chiffre + une barre par jour face à un seuil —
            // ex : « 4,2 % » et trois jours dont deux au-dessus de 3 %.
            case .grandNombreEtJours(let valeur, let jours, let seuil):
                HStack(spacing: 24) {
                    Text(valeur)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(couleur)
                        .monospacedDigit()
                    BarresJoursSeuil(jours: jours, seuil: seuil, couleur: couleur)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(valeur)
                .accessibilityValue(Self.descriptionJours(jours, seuil: seuil))
            }
        }
        // Centrage horizontal de la donnée clé dans la carte — le
        // VStack parent est `.leading`, on étire ici pour permettre
        // au contenu de se centrer.
        .frame(maxWidth: .infinity)
    }

    private static func descriptionJours(_ jours: [Double?], seuil: Double) -> String {
        let auDessus = jours.compactMap { $0 }.filter { $0 > seuil }.count
        let renseignes = jours.compactMap { $0 }.count
        return "\(auDessus) jour\(auDessus > 1 ? "s" : "") sur \(renseignes) au-dessus du seuil"
    }
}

/// Une barre par jour, du plus ancien au plus récent, avec le seuil en trait
/// pointillé. Échelle commune : le seuil tombe à mi-hauteur au minimum, pour
/// que « juste au-dessus » reste lisible. Jour sans donnée : un court trait
/// gris, jamais une barre à zéro (qui dirait « aucune hypo »).
private struct BarresJoursSeuil: View {
    let jours: [Double?]
    let seuil: Double
    let couleur: Color

    private let hauteur: CGFloat = 44

    private var maximum: Double {
        max(seuil * 2, jours.compactMap { $0 }.max() ?? 0)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(jours.enumerated()), id: \.offset) { _, valeur in
                if let valeur {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(valeur > seuil ? couleur : Color.secondary.opacity(0.4))
                        .frame(width: 14, height: max(4, hauteur * valeur / maximum))
                } else {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 14, height: 2)
                }
            }
        }
        .frame(height: hauteur, alignment: .bottom)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.6))
                .frame(height: 0.5)
                .padding(.horizontal, -4)
                .offset(y: -hauteur * seuil / maximum)
        }
    }
}

// MARK: - Aperçus

#if DEBUG
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

#Preview("Chiffre + jours — rouge") {
    MicroVisuelInsight(
        type: .grandNombreEtJours(valeur: "4,2 %", jours: [5.1, 1.8, 5.7], seuil: 3),
        couleur: .red
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
#endif
