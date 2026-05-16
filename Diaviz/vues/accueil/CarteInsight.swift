//
//  CarteInsight.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Carte d'observation individuelle affichée dans
/// `PileVerticaleInsights`. Fond opaque neutre
/// (`secondarySystemGroupedBackground`) — même langage visuel que les
/// cartes « Repas à revoir » juste en dessous, pour homogénéiser la
/// surface des composants standard de l'accueil.
///
/// La couleur de catégorie est **réservée aux éléments clés** : icône
/// d'en-tête, donnée centrale (`MicroVisuelInsight`) et lien « Voir
/// l'analyse → ». Le titre passe en `.primary` et le message reste en
/// `.secondary` — la palette neutre laisse la couleur signaler ce qui
/// mérite l'attention, plutôt que de wash la surface entière.
///
/// **Hiérarchie visuelle** (du plus discret au plus visible) :
///   1. Barre de titre — icône (catégorie) + libellé `.primary`
///      15pt semibold à gauche (aligné sur `CarteScoreQuotidien`),
///      lien « Voir l'analyse → » `.subheadline.bold()` à droite,
///      teinté à la couleur de catégorie.
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
                    .foregroundStyle(.primary)

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
        // Fond opaque neutre — même surface que les cartes « Repas à
        // revoir » juste en dessous, via `Radius.medium` (token unique
        // pour les cartes standard de l'accueil). Pas d'ombre : la
        // séparation avec le fond `systemGroupedBackground` du scroll
        // suffit à détacher la carte sans surcharge visuelle.
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
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
