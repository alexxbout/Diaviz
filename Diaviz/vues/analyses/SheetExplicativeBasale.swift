//
//  SheetExplicativeBasale.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Sheet `.medium` ouverte depuis le bouton « i » de la top bar de
/// `DetailAnalyseBasaleVue` — explique en français simple le principe
/// de l'analyse, les données utilisées, la fréquence de recalcul, la
/// fiabilité, les limites connues, et le disclaimer médical.
///
/// Le contenu est descriptif : aucune section ne prescrit d'ajustement.
/// Toutes les décisions de dose restent du ressort de l'utilisateur et
/// de son médecin (cf. principes du projet, CLAUDE.md).
struct SheetExplicativeBasale: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Comment fonctionne cette analyse")
                    .font(.title3.bold())
                    .padding(.bottom, 16)
                    .accessibilityAddTraits(.isHeader)

                section(
                    titre: "Principe",
                    texte: "Cette analyse observe vos courbes glycémiques pendant les fenêtres de jeûne, principalement la nuit (00h-06h), pour déterminer si votre insuline lente est adaptée. Pendant ces périodes, seule la basale agit sur votre glycémie."
                )

                section(
                    titre: "Données utilisées",
                    texte: "Glycémies nocturnes via votre capteur CGM, historique de vos injections rapides pour calculer l'insuline active résiduelle, et vos repas et activités sportives pour identifier les fenêtres de jeûne valides."
                )

                section(
                    titre: "Fréquence",
                    texte: "L'analyse est recalculée chaque matin à 06h quand la nuit est complète."
                )

                section(
                    titre: "Fiabilité",
                    texte: "Un minimum de 7 nuits analysables est nécessaire pour un premier verdict. 14 nuits permettent un verdict plus fiable. Les nuits avec insuline rapide active, repas récent ou sport récent sont automatiquement exclues."
                )

                section(
                    titre: "Limites",
                    texte: "La consommation d'alcool le soir peut fausser l'analyse. Un changement récent de dose de basale rend les données historiques moins pertinentes. Cette analyse ne couvre pas les problèmes de basale en journée quand de l'insuline rapide est active."
                )

                Text("Cette analyse est descriptive et ne constitue pas un avis médical. Tout ajustement de la dose de basale doit être discuté avec votre médecin.")
                    .font(.caption.italic())
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Une section : titre `.headline` primaire + corps `.body` secondaire.
    /// `fixedSize(...)` empêche la troncation sur les corps multilignes
    /// quand la sheet est en `.medium`.
    private func section(titre: String, texte: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(texte)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Sheet explicative") {
    SheetExplicativeBasale()
}

#Preview("Sheet explicative (sombre)") {
    SheetExplicativeBasale()
        .preferredColorScheme(.dark)
}
#endif
