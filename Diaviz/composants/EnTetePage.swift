//
//  EnTetePage.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// En-tête de page « App Store style » — titre `.largeTitle` à gauche
/// et avatar circulaire (initiale du prénom) à droite, sur la même
/// ligne et sans padding vertical superflu.
///
/// Présent sur les quatre onglets racines (Accueil, Journal, Analyses,
/// Recherche/Chat) pour offrir un accès rapide à la sheet Profil
/// depuis n'importe où dans l'app.
///
/// Le composant gère aussi son propre `@State` d'ouverture de la sheet
/// — chaque onglet n'a qu'à insérer `EnTetePage(titre: "X")` en
/// haut de son contenu, sans avoir à câbler manuellement le binding ni
/// le `.sheet`. La duplication d'état entre onglets est sans conséquence
/// (chaque tab héberge sa propre instance).
struct EnTetePage: View {

    let titre: String

    @Environment(ProfilService.self) private var profilService

    /// Drapeau de présentation de la sheet Profil. Local au composant
    /// — pas besoin de l'exposer puisque le bouton et la sheet vivent
    /// ici.
    @State private var afficherProfil: Bool = false

    var body: some View {
        HStack {
            Text(titre)
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            BoutonProfilAvatar(prenom: profilService.profil.prenom) {
                afficherProfil = true
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $afficherProfil) {
            NavigationStack {
                ProfilVue()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview("Accueil") {
    VStack(spacing: 0) {
        EnTetePage(titre: "Accueil")
        Spacer()
    }
    .environment(ProfilService.mockComplet())
}

#Preview("Profil neuf") {
    VStack(spacing: 0) {
        EnTetePage(titre: "Journal")
        Spacer()
    }
    .environment(ProfilService.mockVide())
}
