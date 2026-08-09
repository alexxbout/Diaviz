//
//  SectionRepasARevoir.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Section « Repas à revoir » de l'accueil — repas dont la dernière réponse
/// glycémique est sortie de cible, qu'ils soient **récurrents**
/// (`CalculRepasARevoir`) ou **contextualisés** (`CalculRepasContexte`).
///
/// Affiche jusqu'à 3 repas : un seul **étendu** en carte détaillée
/// (`CarteRepasARevoir`), les autres en ligne compacte (`LigneRepasARevoir`).
/// Un tap sur une ligne compacte l'échange avec la carte étendue.
///
/// Pas de morph partagé entre les deux formes (essayé via
/// `matchedGeometryEffect`, abandonné : l'interpolation entre une ligne fine
/// et une carte contenant un `Chart` était saccadée, le graphe n'étant pas
/// lui-même une géométrie partagée). À la place, une simple transition
/// d'apparition/disparition (fondu + léger scale) sur chaque forme, animée par
/// le changement de `idEtendu`.
///
/// Auto-masquée si le tableau est vide.
struct SectionRepasARevoir: View {

    let repas: [RepasARevoir]

    /// Ouverture de la liste complète. `nil` → bouton « Tout voir » masqué.
    var onToutVoir: (() -> Void)? = nil

    /// Repas affichés au total sur l'accueil (1 étendu + le reste en lignes
    /// compactes) — au-delà, « Tout voir » prend le relais.
    private static let maxAffiches = 3

    /// Transition partagée par la carte étendue et les lignes compactes : la
    /// forme qui apparaît grandit légèrement depuis 96 %, celle qui disparaît
    /// rétrécit légèrement — lisible comme une bascule, sans prétendre à un
    /// morph continu entre deux mises en page très différentes.
    private static let transitionBascule = AnyTransition.scale(scale: 0.96).combined(with: .opacity)

    /// Id du repas actuellement étendu en carte détaillée. `nil` avant le
    /// premier rendu — initialisé au premier repas de la liste dans `.task`,
    /// pas directement dans l'init (la liste peut être vide au tout premier
    /// rendu, avant que `RepasService` ait fini son fetch).
    @State private var idEtendu: UUID?

    private var affiches: [RepasARevoir] { Array(repas.prefix(Self.maxAffiches)) }
    private var restants: Int { max(repas.count - Self.maxAffiches, 0) }

    var body: some View {
        if !repas.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                entete

                VStack(spacing: 12) {
                    ForEach(affiches) { item in
                        if item.id == idEtendu {
                            CarteRepasARevoir(repas: item)
                                .transition(Self.transitionBascule)
                        } else {
                            LigneRepasARevoir(repas: item) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    idEtendu = item.id
                                }
                            }
                            .surfaceCarte()
                            .transition(Self.transitionBascule)
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            // L'id étendu peut disparaître de la liste (repas résolu, ou
            // reclassé hors du top 3 par un changement de sévérité) : on
            // retombe alors sur le premier affiché plutôt que de laisser
            // les 3 repas réduits sans aucune carte étendue.
            .task(id: repas.map(\.id)) {
                if idEtendu == nil || !affiches.contains(where: { $0.id == idEtendu }) {
                    idEtendu = affiches.first?.id
                }
            }
        }
    }

    /// Titre + compteur, et « Tout voir » à droite dès qu'il reste des repas
    /// non affichés (le compteur du titre porte le total, pas seulement les
    /// 3 montrés).
    private var entete: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Repas à revoir (\(repas.count))")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if restants > 0, let onToutVoir {
                Button("Tout voir", action: onToutVoir)
                    .font(.subheadline)
            }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Un seul repas") {
    ScrollView {
        SectionRepasARevoir(repas: [.mockPadThai])
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Carte + lignes compactes, morph") {
    ScrollView {
        SectionRepasARevoir(repas: [.mockPadThai, .mockPizza, .mockBigMac])
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Avec « Tout voir »") {
    ScrollView {
        SectionRepasARevoir(
            repas: [.mockPadThai, .mockPizza, .mockBigMac, .mockSushi],
            onToutVoir: {}
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Vide") {
    ScrollView {
        SectionRepasARevoir(repas: [])
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Sombre") {
    ScrollView {
        SectionRepasARevoir(repas: [.mockPadThai, .mockPizza])
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
#endif
