//
//  AlimentsCachesSheet.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import SwiftUI

/// Sheet listant les aliments CIQUAL masqués par l'utilisateur, avec
/// possibilité de les restaurer un par un (swipe). Ouverte depuis le menu
/// toolbar d'`AjouterRepasVue`.
struct AlimentsCachesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            contenu
                .navigationTitle("Aliments masqués")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var contenu: some View {
        let aliments = AlimentsCachesService.shared.alimentsCaches

        if aliments.isEmpty {
            ContentUnavailableView(
                "Aucun aliment masqué",
                systemImage: "eye.slash",
                description: Text("Les aliments CIQUAL masqués depuis la recherche (swipe sur une ligne) apparaîtront ici, pour être restaurés si besoin.")
            )
        } else {
            List(aliments) { aliment in
                HStack(spacing: 12) {
                    Text(aliment.emoji ?? "🍽️")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aliment.nom)
                            .font(.body)
                        Text("\(Int(aliment.glucides))g glucides / 100g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        AlimentsCachesService.shared.demasquer(aliment.id)
                    } label: {
                        Label("Restaurer", systemImage: "eye")
                    }
                    .tint(.accentColor)
                }
            }
        }
    }
}

private func _previewAvecUnMasque() -> AlimentsCachesSheet {
    let pomme = AlimentCiqual(id: 1, nom: "Pomme, pulpe et peau, crue", calories: 52, glucides: 12.6, sucres: 10.4, proteines: 0.3, lipides: 0.2, fibres: 2.4, emoji: "🍎")
    AlimentsCachesService.shared.cacher(pomme.id)
    return AlimentsCachesSheet()
}

#Preview {
    _previewAvecUnMasque()
}

#Preview("Vide") {
    AlimentsCachesSheet()
}
