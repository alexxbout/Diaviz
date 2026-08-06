//
//  SectionAlimentsAjoutes.swift
//  diaviz
//

import SwiftUI

/// Section `Form` réutilisable : liste d'aliments ajoutés (recherche,
/// supprimables au swipe) + bouton d'ajout + total glucides dans le header.
/// Facteur commun entre glucides pré-sport (`SheetNouvelleActivite`) et
/// resucrage (`SheetNouveauResucrage`) — même besoin exact : « quels
/// aliments, quelle quantité, combien de glucides au total ».
///
/// **Ne possède pas sa propre présentation** : `onAjouter` délègue
/// l'ouverture de la recherche au parent, qui doit poser `.sheet` à la
/// racine de son `NavigationStack` (même endroit que ses autres alerts/
/// sheets). Une `Section` vit à l'intérieur d'un `List`/`Form` — un
/// modificateur de présentation posé dessus (même sur un vrai type `View`
/// comme ici) reste sujet à un re-host imprévisible dès que le `Form`
/// parent redessine d'autres rows, d'où des fermetures automatiques
/// aléatoires constatées en test. Toujours remonter la présentation au
/// niveau racine de l'écran.
struct SectionAlimentsAjoutes: View {
    let titreSection: String
    let footer: String
    @Binding var aliments: [Aliment]
    let onAjouter: () -> Void

    private var total: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }

    var body: some View {
        Section {
            ForEach(aliments) { aliment in
                HStack(spacing: 12) {
                    Text(aliment.emojiAffiche)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(aliment.nomAffiche)
                            .font(.body)
                        Text("\(aliment.quantite)g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(aliment.glucides)g")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { indices in
                aliments.remove(atOffsets: indices)
            }

            Button(action: onAjouter) {
                Label("Ajouter un aliment", systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text(titreSection)
                if total > 0 {
                    Spacer()
                    Text("Total : \(total)g")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(footer)
        }
    }
}
