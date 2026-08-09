//
//  SheetExplicativeVerdictsResucrage.swift
//  diaviz
//

import SwiftUI

/// Explique comment un resucrage est jugé sur le détail d'une activité —
/// même rôle et même forme que `SheetExplicativeBasale` pour B1.
///
/// Rend l'algorithme lisible plutôt que magique : d'où vient chaque fenêtre
/// d'observation, ce que chaque verdict signifie, et quand rien n'est jugé.
/// Descriptif de bout en bout : aucune quantité n'est recommandée.
struct SheetExplicativeVerdictsResucrage: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Comment un resucrage est jugé")
                    .font(.title3.bold())
                    .padding(.bottom, 16)
                    .accessibilityAddTraits(.isHeader)

                Text("Le verdict compare ce que votre glycémie a fait à ce que vous visiez en prenant ces glucides. C'est l'intention déclarée à la saisie qui définit ce qui compte comme réussi — rien n'est recommandé, seulement observé.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                section(
                    titre: "Correctif hypo",
                    texte: "Jugé 30 minutes après la prise. « Remonté » si votre glycémie repasse au-dessus de votre seuil d'hypoglycémie. « Remonté trop haut » si elle dépasse votre seuil d'hyperglycémie sur la fenêtre : traiter une hypo ne devrait pas créer une hyper. « Insuffisant » si elle reste sous le seuil."
                )

                section(
                    titre: "Préventif maintien",
                    texte: "Jugé jusqu'à la fin de l'effort, avec un minimum de 30 minutes. C'est la durée que vous cherchez à tenir : une fenêtre fixe de 30 minutes ne dirait rien d'une séance d'une heure. « Maintenu » si votre glycémie reste en cible sur toute la fenêtre."
                )

                section(
                    titre: "Préventif anti-chute",
                    texte: "Jugé 30 minutes après la prise, durée d'action d'un glucide à index glycémique élevé. « Chute évitée » si aucune hypoglycémie n'est survenue sur la fenêtre."
                )

                section(
                    titre: "Quand rien n'est jugé",
                    texte: "Si une autre prise arrive avant la fin de la fenêtre, les deux effets se mélangent : les prises forment un même épisode et ne sont pas jugées séparément — le verdict devient « Non évaluable ». Si le capteur a trop peu de mesures sur la période, le verdict est « Indéterminé »."
                )

                section(
                    titre: "Seuils utilisés",
                    texte: "Les verdicts s'appuient sur les seuils de votre profil, les mêmes que partout ailleurs dans l'application. Vous pouvez les modifier dans Réglages."
                )

                Text("Ces verdicts sont descriptifs et ne constituent pas un avis médical. La quantité de glucides à prendre reste votre décision, à discuter avec votre médecin.")
                    .font(.caption.italic())
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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

#if DEBUG
#Preview {
    SheetExplicativeVerdictsResucrage()
}
#endif
