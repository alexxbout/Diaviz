//
//  EncyclopedieVue.swift
//  diaviz
//

import SwiftUI

/// Bibliothèque de synthèses issues de la littérature scientifique,
/// regroupées par thème.
///
/// Volontairement **séparée de l'onglet Analyses** : celui-ci parle des
/// données de l'utilisateur, celle-ci n'en connaît aucune. Mélanger les deux
/// transformerait de la documentation en conseil personnalisé — la frontière
/// que l'app tient depuis le début (cf. CLAUDE.md).
struct EncyclopedieVue: View {

    var body: some View {
        List {
            Section {
                EnTeteAnalyse(
                    surtitre: "Documentation",
                    titre: "Bibliothèque",
                    accroche: "Ce que la littérature établit sur le diabète de type 1, sourcé.",
                    ambiance: .bibliotheque
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Text("Ce que la littérature scientifique établit sur le diabète de type 1, résumé et sourcé. Ces fiches ne tiennent pas compte de vos données et ne constituent pas un avis médical.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 12, trailing: 4))
            }

            ForEach(ThemeEncyclopedie.allCases) { theme in
                let fiches = CatalogueEncyclopedie.fiches(du: theme)
                if !fiches.isEmpty {
                    Section {
                        ForEach(fiches) { fiche in
                            NavigationLink {
                                DetailFicheEncyclopedie(fiche: fiche)
                            } label: {
                                ligne(fiche)
                            }
                        }
                    } header: {
                        Label(theme.rawValue, systemImage: theme.icone)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bibliothèque")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ligne(_ fiche: FicheEncyclopedie) -> some View {
        HStack(spacing: 12) {
            Image(systemName: fiche.icone)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(fiche.titre)
                    .font(.body)
                Text(fiche.resume)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        EncyclopedieVue()
    }
}
#endif
