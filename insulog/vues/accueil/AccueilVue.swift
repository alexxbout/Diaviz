//
//  AccueilVue.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Page d'accueil — pour l'instant essentiellement vide, sert
/// d'enveloppe à `EnTetePage`.
///
/// Header App Store style (titre + avatar sur la même ligne) géré par
/// le composant partagé `EnTetePage`, présent à l'identique sur
/// les quatre onglets racines.
struct AccueilVue: View {

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Accueil")

                // MARK: Contenu (vide pour l'instant)
                Spacer()
            }
        }
    }
}

#Preview("Avec profil complet") {
    AccueilVue()
        .environment(ProfilService.mockComplet())
}

#Preview("Profil neuf") {
    AccueilVue()
        .environment(ProfilService.mockVide())
}
