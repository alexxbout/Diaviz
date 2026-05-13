//
//  InfoLectureGraphe.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Sheet « Lecture du graphe » présentée depuis `GrapheJourneeRepas`
/// (icône info dans le coin supérieur droit). Explique la sémantique
/// visuelle des barres : hauteur (glucides), couleur (verdict),
/// barres estompées (sans injection), interaction tap.
struct InfoLectureGraphe: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Hauteur") {
                    Label("Quantité de glucides du repas", systemImage: "ruler")
                        .labelStyle(.titleAndIcon)
                }

                Section("Couleur") {
                    Text("Verdict glycémique post-repas, dérivé du capteur Dexcom une fois les données disponibles.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ligneVerdict(.bon)
                    ligneVerdict(.moyen)
                    ligneVerdict(.mauvais)
                    ligneVerdict(.indetermine)
                }

                Section("Insuline") {
                    Text("Une barre estompée signale un repas sans injection d'insuline enregistrée.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Tap sur une barre") {
                    Text("Affiche l'heure, la quantité de glucides, le verdict et le délai depuis le dernier repas avec injection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Lecture du graphe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func ligneVerdict(_ v: VerdictGlycemique) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(v.couleur)
                .frame(width: 12, height: 12)
                .frame(width: 24, alignment: .center)
            Text(v.libelle)
                .font(.subheadline)
        }
    }
}

#Preview {
    InfoLectureGraphe()
}
