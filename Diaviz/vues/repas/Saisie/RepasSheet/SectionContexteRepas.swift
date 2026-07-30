//
//  SectionContexteRepas.swift
//  diaviz
//

import SwiftUI

/// Section « Contexte » de `RepasSheet` — texte libre optionnel décrivant un
/// événement particulier (ex. « je prends la voiture »). Non structuré et
/// jamais interprété directement par l'app : exclu de tout mining (voir
/// `Repas.contexteLibre`), affiché tel quel si le verdict est mauvais.
///
/// Chips de suggestion issues du référentiel déjà normalisé
/// (`ReferentielContextesService`, emoji + libellé) — affichées d'emblée,
/// non filtrées par le texte en cours de frappe : l'objectif est de pouvoir
/// taper une suggestion connue immédiatement, sans avoir à retaper le texte
/// brut pour la faire apparaître. Matching local uniquement, aucun appel LLM
/// ici (voir ce service pour la résolution différée après enregistrement).
/// Taper une suggestion recopie son libellé brut (sans emoji) dans le champ,
/// pour rester éditable et matcher instantanément à l'enregistrement.
struct SectionContexteRepas: View {

    @Binding var contexteLibre: String

    private var suggestions: [ContexteNormalise] {
        ReferentielContextesService.shared.entrees
    }

    var body: some View {
        Section {
            TextField("Ex. je prends la voiture", text: $contexteLibre, axis: .vertical)
                .lineLimit(1...3)

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { entree in
                            Button(entree.affichage) { contexteLibre = entree.libelle }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        } header: {
            Text("Contexte")
        } footer: {
            Text("Facultatif — ne modifie ni le ratio ni les analyses, juste affiché tel quel.")
        }
    }
}

// MARK: - Aperçu

#Preview {
    @Previewable @State var contexte = ""
    Form {
        SectionContexteRepas(contexteLibre: $contexte)
    }
}
