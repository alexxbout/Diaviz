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
/// Affiche les repas en **carrousel horizontal** : chaque carte garde son
/// détail complet (`CarteRepasARevoir`, graphe inclus) plutôt que d'en
/// réduire certaines en ligne compacte — l'accueil n'empile plus les cartes
/// verticalement, il laisse parcourir. `Tout voir` reste le seul accès à la
/// liste complète au-delà de `maxAffiches`.
///
/// Quand le tableau est vide, affiche un `CartePlaceholderAccueil` au lieu de
/// se masquer — la structure de l'accueil reste la même avant et après le
/// premier repas sorti de cible.
struct SectionRepasARevoir: View {

    let repas: [RepasARevoir]

    /// Ouverture de la liste complète. `nil` → bouton « Tout voir » masqué.
    var onToutVoir: (() -> Void)? = nil

    /// Repas affichés au total sur l'accueil — au-delà, « Tout voir » prend
    /// le relais.
    private static let maxAffiches = 6

    /// Largeur fixe de chaque carte du carrousel — assez pour garder le
    /// graphe lisible, assez étroit pour laisser deviner la carte suivante.
    private static let largeurCarte: CGFloat = 300

    /// Hauteur fixe commune — toutes les cartes du carrousel doivent faire
    /// la même taille, quel que soit le nombre de badges ou d'événements du
    /// repas le plus chargé. Calibrée large (aliments, badges d'ajustement,
    /// graphe, verdict, récurrence, jusqu'à 4 événements en légende).
    private static let hauteurCarte: CGFloat = 420

    private var affiches: [RepasARevoir] { Array(repas.prefix(Self.maxAffiches)) }
    private var restants: Int { max(repas.count - Self.maxAffiches, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            entete

            if repas.isEmpty {
                // Pas de compteur de progression ici, contrairement aux
                // tendances ou aux glucides : « repas à revoir » n'attend
                // aucun seuil de volume (un seul repas sorti de cible suffit
                // à remonter). Afficher une barre laisserait croire à une
                // collecte en cours qui n'existe pas.
                CartePlaceholderAccueil(
                    icone: "fork.knife",
                    message: "Les repas dont la glycémie est sortie de cible s'afficheront ici."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(affiches) { item in
                            CarteRepasARevoir(repas: item)
                                .frame(width: Self.largeurCarte, height: Self.hauteurCarte)
                        }
                    }
                    .scrollTargetLayout()
                }
                // Contrainte explicite : un `ScrollView` horizontal sans
                // largeur imposée peut remonter la largeur idéale de son
                // contenu (toutes les cartes bout à bout) à ses ancêtres et
                // élargir toute la page — même symptôme, même fix, que le
                // graphique de la carte ratios (colonnes fixes trop
                // larges) : un contenu à largeur non compressible force son
                // conteneur à s'élargir s'il n'est pas explicitement borné.
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollTargetBehavior(.viewAligned)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Titre + compteur, et « Tout voir » à droite dès qu'il reste des repas
    /// non affichés (le compteur du titre porte le total, pas seulement ceux
    /// montrés dans le carrousel).
    private var entete: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(repas.isEmpty ? "Repas à revoir" : "Repas à revoir (\(repas.count))")
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

#Preview("Carrousel") {
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

#Preview("Vide (placeholder)") {
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
