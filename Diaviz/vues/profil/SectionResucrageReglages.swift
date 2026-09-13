//
//  SectionResucrageReglages.swift
//  diaviz
//

import SwiftUI

/// Section « RESUCRAGE » de la sheet Profil — règle la fenêtre d'affichage
/// de `CarteResucrageRecent` sur l'accueil. Même pattern que
/// `SectionRepasARevoirReglages`.
struct SectionResucrageReglages: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Section {
            Stepper(
                "Visible \(fenetreHeures)h après la prise",
                value: bindingFenetreHeures,
                in: 1...12
            )
        } header: {
            Text("Resucrage")
        } footer: {
            Text("""
            Durée pendant laquelle la carte « Dernier resucrage » reste \
            affichée sur l'accueil après une prise. Passé ce délai, elle \
            disparaît de l'accueil — elle reste toujours visible sur la \
            page Resucrage elle-même.
            """)
        }

        Section {
            Stepper(
                "\(glucidesRapides) g par défaut",
                value: bindingGlucidesRapides,
                in: 5...60,
                step: 5
            )
        } header: {
            Text("Ajout rapide")
        } footer: {
            Text("""
            Quantité pré-remplie par le bouton d'ajout rapide dans la sheet \
            resucrage — enregistre directement un aliment générique « \
            Glucides rapides » sans passer par la recherche.
            """)
        }
    }

    private var fenetreHeures: Int {
        service.profil.preferencesAvancees.fenetreAffichageResucrageAccueilHeures
            ?? CarteResucrageRecent.fenetreAccueilParDefautHeures
    }

    private var bindingFenetreHeures: Binding<Int> {
        Binding(
            get: { fenetreHeures },
            set: { nouvelle in
                service.mettreAJour {
                    $0.preferencesAvancees.fenetreAffichageResucrageAccueilHeures = nouvelle
                }
            }
        )
    }

    private var glucidesRapides: Int {
        service.profil.preferencesAvancees.glucidesResucrageRapideParDefaut
            ?? SheetNouveauResucrage.glucidesRapidesParDefaut
    }

    private var bindingGlucidesRapides: Binding<Int> {
        Binding(
            get: { glucidesRapides },
            set: { nouvelle in
                service.mettreAJour {
                    $0.preferencesAvancees.glucidesResucrageRapideParDefaut = nouvelle
                }
            }
        )
    }
}

#if DEBUG
#Preview {
    Form {
        SectionResucrageReglages()
    }
    .formStyle(.grouped)
    .environment(ProfilService.mockComplet())
}
#endif
