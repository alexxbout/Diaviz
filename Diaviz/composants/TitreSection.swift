//
//  TitreSection.swift
//  diaviz
//

import SwiftUI

/// Titre de groupe posé **hors carte**, sur le fond de page — le même que
/// « Aujourd'hui » ou « Aperçu du jour » sur l'accueil.
///
/// Sert à rendre l'espacement signifiant : sans titre, une page qui empile
/// six cartes au même écart ne dit pas lesquelles répondent à la même
/// question, et l'œil doit lire chaque en-tête interne pour se repérer.
/// Avec des groupes nommés, l'espace devient l'information — serré à
/// l'intérieur d'un groupe, large entre deux.
///
/// Ne vaut qu'au-delà de trois ou quatre blocs : sur une page à deux cartes,
/// un titre structure ce qui n'a rien à structurer.
struct TitreSection: View {

    let texte: String

    var body: some View {
        Text(texte)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            // 4pt : aligne le titre sur le texte des cartes, qui portent 16pt
            // de padding interne mais commencent 4pt plus à gauche que leur
            // contenu — même valeur que sur l'accueil.
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Verdict")
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: 90)
            }
            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Nuit par nuit")
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: 140)
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: 80)
            }
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
