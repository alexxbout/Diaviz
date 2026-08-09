//
//  LigneResultatRecherche.swift
//  diaviz
//
//  Created by Alexandre on 27/04/2026.
//

import SwiftUI

// Row d'un résultat de recherche d'aliment (recherche CIQUAL/OFF, ou aliment
// récent) — première étape du flux de saisie, avant même que l'aliment ne
// soit ajouté au repas en cours.
//
// À ne pas confondre avec les deux autres rows du domaine repas :
// - `LigneAlimentEnCours` (RepasSheet/) : l'aliment une fois ajouté au repas
//   en cours de composition, éditable/supprimable.
// - `CarteAlimentEnregistre` (composants/) : l'aliment tel qu'affiché dans un
//   repas déjà persisté dans le hub (journal, détail).
//
// Row purement d'affichage : le tap est géré par la vue parente
// (`AjouterRepasVue`) via un `.simultaneousGesture`, qui ouvre la sheet de
// configuration puis marque l'aliment comme récent à la validation. La row ne
// déclenche donc AUCUNE action elle-même (sinon `marquerUtilise` serait appelé
// deux fois : au tap ici, puis à la validation de la sheet).
struct LigneResultatRecherche: View {
    let aliment: ResultatRechercheAliment

    var body: some View {
        HStack(spacing: 12) {
            VignetteAliment(aliment: aliment, taille: 36)
            VStack(alignment: .leading) {
                if AlimentsRecentsService.shared.estRecent(aliment) {
                    Text("Récemment ajouté")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
                Text(aliment.nom)
                    .font(.body)
                if let marque = aliment.marque {
                    Text(marque)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if aliment.glucidesRenseignes {
                    Text("\(Int(aliment.glucides))g glucides / 100g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Glucides non renseignés")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    let pomme = AlimentCiqual(id: 1, nom: "Pomme, pulpe et peau, crue", calories: 52, glucides: 12.6, sucres: 10.4, proteines: 0.3, lipides: 0.2, fibres: 2.4, emoji: "🍎")
    let nutella = AlimentOFF(code: "3017620422003", nom: "Nutella", marque: "Ferrero", calories: 539, glucides: 57.5, sucres: 56.3, proteines: 6.3, lipides: 30.9, fibres: nil, imagePetiteURL: nil, imageURL: nil)
    let mystere = AlimentOFF(code: "123", nom: "Produit sans nutriments", marque: nil, calories: nil, glucides: nil, sucres: nil, proteines: nil, lipides: nil, fibres: nil, imagePetiteURL: nil, imageURL: nil)

    List {
        LigneResultatRecherche(aliment: .ciqual(pomme))
        LigneResultatRecherche(aliment: .off(nutella))
        LigneResultatRecherche(aliment: .off(mystere))
    }
}
#endif
