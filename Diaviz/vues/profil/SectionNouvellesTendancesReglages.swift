//
//  SectionNouvellesTendancesReglages.swift
//  diaviz
//

import SwiftUI

/// Section « Nouvelles tendances » du Profil : affiche ou non, dans la pile
/// de l'accueil, les cartes de courbe des repas et des séances.
struct SectionNouvellesTendancesReglages: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Section("Nouvelles tendances") {
            Toggle("Courbes des repas et des séances", isOn: bindingAfficherCourbes)
        }
    }

    private var bindingAfficherCourbes: Binding<Bool> {
        Binding(
            get: { service.profil.preferencesAvancees.cartesCourbesInsightsActives ?? true },
            set: { nouvelle in
                service.mettreAJour {
                    $0.preferencesAvancees.cartesCourbesInsightsActives = nouvelle
                }
            }
        )
    }
}

#if DEBUG
#Preview {
    Form {
        SectionNouvellesTendancesReglages()
    }
    .formStyle(.grouped)
    .environment(ProfilService.mockComplet())
}
#endif
