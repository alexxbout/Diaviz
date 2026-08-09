//
//  CarteAlimentEnregistre.swift
//  diaviz
//
//  Created by Alexandre on 22/04/2026.
//

import SwiftUI

/// Card d'un aliment appartenant à un repas **déjà persisté** dans le hub
/// (journal, détail d'un repas) — affichage de la forme finale résolue
/// (emoji/photo, nom, quantité, glucides, insuline). Swipeable pour retirer
/// l'aliment du hub selon le contexte parent, mais ne porte elle-même aucune
/// logique d'édition.
///
/// À ne pas confondre avec les deux autres rows du domaine repas :
/// - `LigneResultatRecherche` (Saisie/) : un résultat de recherche, pas
///   encore ajouté à un repas.
/// - `LigneAlimentEnCours` (RepasSheet/) : l'aliment dans un repas encore en
///   cours de composition, non persisté.
struct CarteAlimentEnregistre: View {
    let emoji: String
    let nom: String
    let quantite: Int
    let glucides: Int
    let insuline: Double
    /// Photo du produit (OFF) — prioritaire sur l'emoji quand présente.
    var imageURL: URL? = nil
    /// Pris pour traiter une hypoglycémie plutôt qu'un aliment de repas
    /// ordinaire — affiché en rouge, même traitement visuel que "sans
    /// insuline" dans `LigneRepas`.
    var resucrage: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Vignette réduite (28pt) : l'aliment est un détail sous l'en-tête
            // du repas, pas un pair. En `largeTitle` l'emoji pesait autant que
            // le titre du repas et écrasait la hiérarchie de la section.
            if let imageURL {
                ImageProduit(url: imageURL, coinArrondi: 6)
                    .frame(width: 28, height: 28)
            } else {
                Text(emoji)
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }

            Text(nom)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)

            if resucrage {
                badgeResucrage
            }

            Spacer(minLength: 8)

            Text("\(quantite)g")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            // Dose par aliment masquée quand elle vaut 0 : en mode dose
            // globale, `enregistrerDepuisSaisie` remet chaque aliment à 0 (la
            // dose vit sur le repas) — afficher « 0u » sur toutes les rows
            // laissait croire à un repas non bolussé.
            if insuline > 0 {
                Text(insuline.doseInsulineFormatee)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("\(glucides)g")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .trailing)
        }
    }

    /// Badge capsule rouge signalant un aliment de resucrage — même logique
    /// de lecture immédiate qu'un tag iOS natif (Rappels, Mail).
    private var badgeResucrage: some View {
        Text("Resucrage")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red, in: Capsule())
            .layoutPriority(1)
            .fixedSize()
    }
}

#if DEBUG
#Preview {
    VStack {
        CarteAlimentEnregistre(emoji: "🍚", nom: "Riz basmati", quantite: 60, glucides: 27, insuline: 2.0)
        CarteAlimentEnregistre(emoji: "🍬", nom: "Sucre blanc", quantite: 10, glucides: 10, insuline: 0, resucrage: true)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.secondarySystemBackground))
}
#endif
