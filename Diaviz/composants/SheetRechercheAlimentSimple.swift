//
//  SheetRechercheAlimentSimple.swift
//  diaviz
//

import SwiftUI

/// Recherche d'aliment allégée — même moteur (`CiqualService`, `LigneResultatRecherche`,
/// aliments récents) que la saisie repas, mais sans dose d'insuline ni flag
/// resucrage : sert aux contextes où on ne veut que « quel aliment, quelle
/// quantité ».
///
/// Partagée par la saisie d'un resucrage et celle des glucides pré-sport,
/// d'où sa place dans `composants/` — elle est arrivée par le domaine sport
/// mais ne lui appartient pas.
///
/// Contrairement à `AjouterRepasVue`, pas de scan code-barres/OFF : recherche
/// CIQUAL uniquement, suffisant pour ce besoin, pas de raison d'embarquer
/// VisionKit ici.
struct SheetRechercheAlimentSimple: View {

    let titre: String
    let onValider: (Aliment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recherche = ""
    @State private var resultats: [AlimentCiqual] = []
    @State private var resultatChoisi: ResultatRechercheAliment?

    var body: some View {
        NavigationStack {
            List {
                if recherche.isEmpty {
                    sectionRecents
                } else if resultats.isEmpty {
                    ContentUnavailableView.search(text: recherche)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(resultats) { aliment in
                        LigneResultatRecherche(aliment: .ciqual(aliment))
                            .contentShape(Rectangle())
                            .onTapGesture { resultatChoisi = .ciqual(aliment) }
                    }
                }
            }
            .searchable(text: $recherche, prompt: "Rechercher un aliment")
            .onChange(of: recherche) { _, nouveau in
                resultats = nouveau.isEmpty ? [] : CiqualService.shared.rechercher(nouveau)
            }
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .sheet(item: $resultatChoisi) { resultat in
            SheetQuantiteAlimentSimple(aliment: resultat) { aliment in
                onValider(aliment)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var sectionRecents: some View {
        // CIQUAL uniquement — même limite que la recherche elle-même (pas de
        // scan OFF ici), sinon un produit OFF récent (via la saisie repas)
        // apparaîtrait alors qu'il n'est pas cherchable dans cette sheet.
        let recents = AlimentsRecentsService.shared.alimentsRecents
            .filter { if case .ciqual = $0 { return true }; return false }
            .prefix(10)
        if !recents.isEmpty {
            Section("Récents") {
                ForEach(recents) { aliment in
                    LigneResultatRecherche(aliment: aliment)
                        .contentShape(Rectangle())
                        .onTapGesture { resultatChoisi = aliment }
                }
            }
        }
    }
}

// MARK: - Aperçu

#Preview {
    SheetRechercheAlimentSimple(titre: "Glucides pré-sport", onValider: { _ in })
}
