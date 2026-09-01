//
//  TitreSectionListe.swift
//  diaviz
//

import SwiftUI

/// En-tête de `Section` pour les `List` en `.insetGrouped` — en clair plutôt
/// qu'en petites capitales grises.
///
/// Les pages du Journal (repas, médications, sport, resucrage) sont des
/// `List` et non des piles de cartes : les convertir pour y poser un
/// `TitreSection` coûterait les séparateurs natifs, le swipe-to-delete et le
/// comportement de cellule, pour un gain purement visuel. Elles gardent donc
/// leur `List` et cet en-tête leur donne l'allure des sections nommées de
/// l'accueil et des analyses.
///
/// Un cran plus petit que `TitreSection` (`title3` contre `title2`) : ces
/// titres se répètent beaucoup plus dans une liste — un par moment de repas,
/// un par jour de resucrage — là où une page d'analyse en compte trois.
///
/// Composant partagé et non recopié dans chaque vue : c'est précisément ce
/// qui avait fait diverger deux pages du Journal des deux autres.
struct TitreSectionListe: View {

    let texte: String

    var body: some View {
        Text(texte)
            .font(.title3.bold())
            .foregroundStyle(.primary)
            // Annule la mise en majuscules automatique des en-têtes de
            // `List.insetGrouped`.
            .textCase(nil)
    }
}

#if DEBUG
#Preview {
    List {
        Section {
            Text("Flocons d'avoine")
            Text("Banane")
        } header: {
            TitreSectionListe(texte: "Petit déjeuner")
        }
        Section {
            Text("Pâtes complètes")
        } header: {
            TitreSectionListe(texte: "Déjeuner")
        }
    }
    .listStyle(.insetGrouped)
    .listSectionSpacing(24)
}
#endif
