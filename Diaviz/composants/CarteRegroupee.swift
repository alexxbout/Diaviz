//
//  CarteRegroupee.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Conteneur en forme de carte « groupée » (style iOS) — surface opaque au
/// niveau `.carte`, sans padding interne. Les enfants se placent eux-mêmes
/// pour pouvoir afficher des séparateurs pleine largeur.
///
/// Utilisée dans les pages de détail (Repas, Activité) pour regrouper
/// des `LigneMetrique` ou des listes d'aliments.
struct CarteRegroupee<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
    }
}
