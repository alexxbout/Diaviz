//
//  EtatIndisponibleGraphique.swift
//  insulog
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Vue partagée pour les états « non disponible » d'un graphique
/// glycémique (en attente, données manquantes, sans analyse).
/// Centralise icône + titre + description en pile centrée.
///
/// Utilisée par `GraphiqueGlycemique` pour les trois cas où la
/// courbe ne peut pas être tracée — remplace les anciennes
/// `EtatIndisponible` (repas) et `EtatIndisponibleSport` qui étaient
/// identiques mot pour mot.
struct EtatIndisponibleGraphique: View {

    let icone: String
    let titre: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icone)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(titre)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre). \(description)")
    }
}
