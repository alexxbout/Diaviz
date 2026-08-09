//
//  AlimentsRenommesSheet.swift
//  diaviz
//

import SwiftUI

/// Sheet listant les aliments CIQUAL personnalisés (nom et/ou emoji) par
/// l'utilisateur, avec restauration individuelle par swipe (nom, emoji, ou
/// les deux selon ce qui est personnalisé pour cet aliment). Ouverte depuis
/// le menu toolbar d'`AjouterRepasVue`.
struct AlimentsRenommesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            contenu
                .navigationTitle("Aliments renommés")
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
        let aliments = NomsPersonnalisesService.shared.alimentsPersonnalises

        if aliments.isEmpty {
            ContentUnavailableView(
                "Aucun aliment renommé",
                systemImage: "pencil",
                description: Text("Les aliments CIQUAL renommés depuis leur fiche de détail apparaîtront ici.")
            )
        } else {
            List(aliments) { aliment in
                HStack(spacing: 12) {
                    Text(NomsPersonnalisesService.shared.emoji(pour: aliment) ?? "🍽️")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NomsPersonnalisesService.shared.nom(pour: aliment))
                            .font(.body)
                        Text(aliment.nom)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if NomsPersonnalisesService.shared.nomPersonnalise(pour: aliment.id) != nil {
                        Button {
                            NomsPersonnalisesService.shared.restaurerNom(aliment.id)
                        } label: {
                            Label("Restaurer le nom", systemImage: "textformat")
                        }
                        .tint(.accentColor)
                    }
                    if NomsPersonnalisesService.shared.emojiPersonnalise(pour: aliment.id) != nil {
                        Button {
                            NomsPersonnalisesService.shared.restaurerEmoji(aliment.id)
                        } label: {
                            Label("Restaurer l'emoji", systemImage: "face.smiling")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }
}

private func _previewAvecUnRenomme() -> AlimentsRenommesSheet {
    let pomme = AlimentCiqual(id: 1, nom: "Pomme, pulpe et peau, crue", calories: 52, glucides: 12.6, sucres: 10.4, proteines: 0.3, lipides: 0.2, fibres: 2.4, emoji: "🍎")
    NomsPersonnalisesService.shared.renommer(pomme.id, en: "Ma pomme du matin")
    return AlimentsRenommesSheet()
}

#if DEBUG
#Preview {
    _previewAvecUnRenomme()
}

#Preview("Vide") {
    AlimentsRenommesSheet()
}
#endif
