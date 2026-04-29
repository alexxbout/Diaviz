//
//  ListeAlimentsSection.swift
//  insulog
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Section "ALIMENTS" de la `RepasSheet` : liste des entrées du repas en cours
/// avec édition au tap, suppression au swipe, et bouton "Ajouter un aliment"
/// en queue de section.
///
/// Les actions sont remontées au parent via deux closures pour ne pas
/// coupler la section à la logique de présentation des sheets enfants.
struct ListeAlimentsSection: View {

    @Binding var aliments: [EntreeAliment]

    /// Tap sur une row → édition de l'entrée correspondante.
    let onEditer: (EntreeAliment) -> Void

    /// Tap sur "Ajouter un aliment" → fermer la sheet et rendre la barre
    /// de recherche active dans la vue parente.
    let onAjouterUnAliment: () -> Void

    var body: some View {
        Section {
            ForEach(aliments) { entree in
                LigneAlimentRepas(entree: entree)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEditer(entree)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            supprimer(entree)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
            }

            // Row "Ajouter un aliment" intégrée à la section.
            // En .body avec tint, sans icône bold pour rester discret.
            Button(action: onAjouterUnAliment) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.body)
                    Text("Ajouter un aliment")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.tint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("Aliments")
                // En-tête de section style Form natif iOS, déjà en uppercase.
        }
    }

    private func supprimer(_ entree: EntreeAliment) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            aliments.removeAll { $0.id == entree.id }
        }
    }
}
