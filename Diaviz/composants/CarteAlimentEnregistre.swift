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
                Text("\(quantite)g")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
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
}

#Preview {
    VStack {
        CarteAlimentEnregistre(emoji: "🍚", nom: "Riz basmati", quantite: 60, glucides: 27, insuline: 2.0)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.secondarySystemBackground))
}
