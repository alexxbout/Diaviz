//
//  RechercheVue.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Onglet « Recherche / Chat » — placeholder pour l'instant. Reçoit
/// l'en-tête `EnTetePage` comme les trois autres onglets pour
/// que l'avatar Profil soit accessible depuis n'importe où.
struct RecercheVue: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Chat")

                Spacer()
            }
        }
    }
}

#Preview {
    RecercheVue()
        .environment(ProfilService.mockComplet())
}
