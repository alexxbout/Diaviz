//
//  AlimentsCorrigesSheet.swift
//  diaviz
//

import SwiftUI

/// Sheet listant les aliments dont les glucides pour 100 g ont été rectifiés,
/// avec restauration de la valeur d'origine par swipe. Ouverte depuis le menu
/// toolbar d'`AjouterRepasVue`, même pattern qu'`AlimentsCachesSheet` et
/// `AlimentsRenommesSheet`.
///
/// Un produit Open Food Facts corrigé conserve son snapshot même sorti de la
/// liste des récents (voir `AlimentsRecentsService.nettoyerSnapshots`) : sans
/// lui, la correction s'afficherait ici sans nom ni marque.
struct AlimentsCorrigesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var service: AlimentsRecentsService { .shared }

    var body: some View {
        NavigationStack {
            contenu
                .navigationTitle("Glucides corrigés")
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
        let aliments = service.alimentsCorriges

        if aliments.isEmpty {
            ContentUnavailableView(
                "Aucun aliment corrigé",
                systemImage: "pencil",
                description: Text("Les aliments dont tu as rectifié les glucides pour 100 g, depuis leur fiche de détail, apparaîtront ici.")
            )
        } else {
            List(aliments) { aliment in
                HStack(spacing: 12) {
                    VignetteAliment(aliment: aliment, taille: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aliment.nom)
                            .font(.body)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text("\(formate(aliment.glucides))g / 100g")
                                .foregroundStyle(Color.accentColor)
                            Text("· d'origine \(formate(aliment.glucidesOrigine))g")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .lineLimit(1)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        service.restaurerGlucides(aliment)
                    } label: {
                        Label("Restaurer", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.accentColor)
                }
            }
        }
    }

    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Vide") {
    AlimentsCorrigesSheet()
}
#endif
