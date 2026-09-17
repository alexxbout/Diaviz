//
//  PageTousRepasARevoir.swift
//  diaviz
//

import SwiftUI

/// Page « Tout voir » de la section accueil « Repas à revoir » — pushée
/// depuis la carte résumé du même nom (`SectionRepasARevoir`). Seul point
/// d'accès au détail complet désormais : l'accueil n'affiche plus qu'un
/// compteur et une répartition, cette page porte toutes les cartes.
///
/// Repas groupés **par moment de la journée** (`SectionRepas.allCases`,
/// ordre chronologique) — cohérent avec le regroupement déjà utilisé par
/// l'analyse des ratios. Un moment sans repas à revoir n'affiche aucune
/// section, plutôt qu'un titre suivi de rien.
struct PageTousRepasARevoir: View {

    let repas: [RepasARevoir]

    /// Un groupe par moment non vide, dans l'ordre chronologique de la
    /// journée. `libelleSection` est déjà dérivé de `SectionRepas(heure:horaires:).titre`
    /// à la construction (`CalculRepasARevoir`/`CalculRepasIsoles`) — la
    /// comparaison de chaînes suffit, pas besoin de reclasser une heure ici.
    private var groupes: [(titre: String, items: [RepasARevoir])] {
        SectionRepas.allCases.compactMap { section in
            let items = repas.filter { $0.libelleSection == section.titre }
            return items.isEmpty ? nil : (section.titre, items)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                EnTeteAnalyse(
                    surtitre: "Analyse des repas",
                    titre: "Repas à revoir",
                    accroche: "Les plats dont la dernière glycémie est sortie de cible, et ceux pris dans un contexte particulier.",
                    ambiance: .repasARevoir
                )
                ForEach(groupes, id: \.titre) { groupe in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(groupe.titre)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .padding(.leading, 4)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(groupe.items) { item in
                            CarteRepasARevoir(repas: item)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Repas à revoir")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    NavigationStack {
        PageTousRepasARevoir(repas: [.mockPadThai, .mockPizza, .mockBigMac, .mockSushi])
    }
}

#Preview("Vide") {
    NavigationStack {
        PageTousRepasARevoir(repas: [])
    }
}
#endif
