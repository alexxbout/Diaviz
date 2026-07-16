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
        HStack {
            if let imageURL {
                ImageProduit(url: imageURL)
                    .frame(width: 40, height: 40)
            } else {
                Text(emoji)
                    .font(.largeTitle)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(nom)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text("\(quantite)g")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    if resucrage {
                        badgeResucrage
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(glucides)g")
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                Text(insuline.doseInsulineFormatee)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    /// Badge capsule rouge signalant un aliment de resucrage — même logique
    /// de lecture immédiate qu'un tag iOS natif (Rappels, Mail).
    private var badgeResucrage: some View {
        Text("Resucrage")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.red, in: Capsule())
            .layoutPriority(1)
    }
}

#Preview {
    VStack {
        CarteAlimentEnregistre(emoji: "🍚", nom: "Riz basmati", quantite: 60, glucides: 27, insuline: 2.0)
        CarteAlimentEnregistre(emoji: "🍬", nom: "Sucre blanc", quantite: 10, glucides: 10, insuline: 0, resucrage: true)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.secondarySystemBackground))
}
