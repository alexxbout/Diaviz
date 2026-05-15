//
//  CarteInsight.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Carte d'observation individuelle affichée dans la pile
/// `PileInsights`. Fond Liquid Glass (`.glassEffect`) tinté à la
/// couleur de la catégorie — le matériau **blurre** ce qu'il y a
/// derrière (= les autres cartes empilées) et reste lisible, ce que
/// ne permettait pas un fond translucide plat. La drop shadow
/// naturelle du glass renforce la perception de profondeur de la pile.
///
/// Structure interne VStack(alignment: .leading, spacing: 8) :
///   1. Header — icône SF Symbol + titre
///   2. Micro-visuel (optionnel selon `MicroVisuelType`)
///   3. Message court (2 lignes max)
///   4. Lien « Voir l'analyse → » aligné en bas à droite
///
/// La carte n'est volontairement pas un `Button` pour l'instant : la
/// page Analyses cible n'a pas encore d'identifiant routable. Le lien
/// reste un indicateur visuel.
struct CarteInsight: View {

    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // MARK: Header — icône + titre
            HStack(spacing: 6) {
                Image(systemName: insight.categorie.icone)
                    .font(.subheadline)
                    .foregroundStyle(insight.categorie.couleur)
                    .accessibilityHidden(true)
                Text(insight.titre)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }

            // MARK: Micro-visuel — n'occupe pas de place si `.aucun`
            MicroVisuelInsight(
                type: insight.microVisuel,
                couleur: insight.categorie.couleur
            )

            // MARK: Message court — descriptif, jamais prescriptif
            Text(insight.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Pousse le lien en bas de la carte quel que soit le
            // contenu du dessus — important pour aligner les liens
            // entre pages du TabView.
            Spacer(minLength: 0)

            // MARK: Lien — couleur de la catégorie
            HStack {
                Spacer()
                Text("Voir l'analyse →")
                    .font(.caption.bold())
                    .foregroundStyle(insight.categorie.couleur)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(
            // `.interactive()` = la surface glass se déforme fluidement
            // sous le doigt (signature Liquid Glass iOS 26).
            // Tint à 0.30 pour mieux affirmer la couleur de catégorie.
            .regular.tint(insight.categorie.couleur.opacity(0.30)).interactive(),
            in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.titre). \(insight.message)")
        .accessibilityHint("Voir l'analyse détaillée")
    }
}

// MARK: - Aperçus

#Preview("Carte - Informatif bleu") {
    CarteInsight(insight: .mockImpactSport)
        .padding()
        .frame(height: 160)
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Attention orange") {
    CarteInsight(insight: .mockRatioMidi)
        .padding()
        .frame(height: 160)
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Action violet") {
    CarteInsight(insight: .mockAnalyseCardio)
        .padding()
        .frame(height: 160)
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Basale orange") {
    CarteInsight(insight: .mockBasale)
        .padding()
        .frame(height: 160)
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Sombre") {
    CarteInsight(insight: .mockImpactSport)
        .padding()
        .frame(height: 160)
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
