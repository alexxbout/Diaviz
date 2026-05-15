//
//  CarteInsight.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Carte d'observation individuelle affichée dans
/// `PileVerticaleInsights`. Fond Liquid Glass pur, sans tint coloré :
/// on veut sentir la refraction et le morphing de la glass plutôt
/// qu'une surcouche translucide colorée. La couleur de catégorie
/// reste portée par l'icône du titre, la donnée clé et le lien.
///
/// **Hiérarchie visuelle** (du plus discret au plus visible) :
///   1. Barre de titre — icône + libellé 15pt semibold à gauche
///      (aligné sur `CarteScoreQuotidien`), lien « Voir l'analyse → »
///      `.subheadline.bold()` à droite. Tout à la couleur de la catégorie.
///   2. Donnée clé — **dominante** (40pt), centrée, couleur de la catégorie
///   3. Message — moyen (`.callout .secondary`), 2 lignes max
///
/// La carte n'est volontairement pas un `Button` pour l'instant : la
/// page Analyses cible n'a pas encore d'identifiant routable. Le lien
/// reste un indicateur visuel.
struct CarteInsight: View {

    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // MARK: 1. Barre de titre — titre à gauche, lien à droite
            // Titre aligné sur `CarteScoreQuotidien` (15pt semibold),
            // tous deux tintés à la couleur de la catégorie. Le lien
            // « Voir l'analyse → » est placé à droite de la barre pour
            // libérer le bas de la carte au profit du message — et
            // pour reprendre le pattern « chevron / action » de la
            // carte de score (icône + titre à gauche, action à droite).
            HStack(spacing: 6) {
                Image(systemName: insight.categorie.icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(insight.categorie.couleur)
                    .accessibilityHidden(true)
                Text(insight.titre)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(insight.categorie.couleur)

                Spacer(minLength: 8)

                Text("Voir l'analyse →")
                    .font(.subheadline.bold())
                    .foregroundStyle(insight.categorie.couleur)
            }

            // Pousse la donnée clé au centre vertical de la carte.
            Spacer(minLength: 0)

            // MARK: 2. Donnée clé — dominante, centrée horizontalement
            // `MicroVisuelInsight` se charge du centrage horizontal via
            // sa propre `frame(maxWidth: .infinity)`.
            MicroVisuelInsight(
                type: insight.microVisuel,
                couleur: insight.categorie.couleur
            )

            // Espace symétrique sous la donnée clé — la pousse au
            // centre vertical entre le titre et le bloc message/lien.
            Spacer(minLength: 0)

            // MARK: 3. Message — explication courte, 2 lignes max
            Text(insight.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(
            // `.interactive()` = la surface glass se déforme fluidement
            // sous le doigt (signature Liquid Glass iOS 26).
            // Pas de `.tint(...)` : la glass reste claire, on perçoit
            // mieux la refraction et le morphing. La couleur de
            // catégorie est portée par l'icône du titre, la donnée
            // clé et le lien — ça suffit comme repère.
            .regular.interactive(),
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
        .frame(height: 180)
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Attention orange") {
    CarteInsight(insight: .mockRatioMidi)
        .padding()
        .frame(height: 180)
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Action violet") {
    CarteInsight(insight: .mockAnalyseCardio)
        .padding()
        .frame(height: 180)
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Basale orange") {
    CarteInsight(insight: .mockBasale)
        .padding()
        .frame(height: 180)
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Sombre") {
    CarteInsight(insight: .mockImpactSport)
        .padding()
        .frame(height: 180)
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
