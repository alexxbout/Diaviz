//
//  SectionContexteRepas.swift
//  diaviz
//

import SwiftUI

/// Section « Événements » de `RepasSheet` — circonstances de vie du repas
/// (« 🚘 Voiture », « 🍽️ Restaurant »), optionnelles.
///
/// Ne fait qu'**afficher** la sélection courante et ouvrir
/// `SheetEvenementsRepas` : la saisie, la génération du libellé et le choix
/// dans le référentiel vivent tous là-bas, exactement comme après
/// enregistrement depuis le détail d'un repas. Le champ texte + chips
/// d'origine ont été retirés d'ici pour ne pas maintenir deux UI divergentes
/// de la même donnée.
struct SectionContexteRepas: View {

    let evenements: [EvenementRepas]
    let onEditer: () -> Void

    var body: some View {
        Section {
            Button(action: onEditer) {
                HStack(spacing: 10) {
                    if evenements.isEmpty {
                        Label("Ajouter un événement", systemImage: "tag")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        RangeeBadges(items: evenements.map {
                            ItemBadge($0.affichageResolu, couleur: .purple)
                        })
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("Événements")
        } footer: {
            Text("Facultatif. Un repas portant un événement est exclu de l'analyse des ratios.")
        }
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Avec événements") {
    Form {
        SectionContexteRepas(
            evenements: [
                EvenementRepas(libelle: "Voiture", emoji: "🚘"),
                EvenementRepas(libelle: "Stress boulot", emoji: "😰"),
            ],
            onEditer: {}
        )
    }
    .formStyle(.grouped)
}

#Preview("Vide") {
    Form {
        SectionContexteRepas(evenements: [], onEditer: {})
    }
    .formStyle(.grouped)
}
#endif
