//
//  SousPagesProfil.swift
//  diaviz
//

import SwiftUI

// MARK: - Insuline

/// Sous-page « Insuline » — types rapide/lente, durée d'action (DIA) et
/// intervalle minimum entre deux lentes.
struct SousPageInsuline: View {
    var body: some View {
        Form {
            SectionInsuline()
        }
        .formStyle(.grouped)
        .navigationTitle("Insuline")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Ratios

/// Sous-page « Ratios » — regroupe les trois familles de ratios, qui
/// répondent toutes à la même question (« combien d'insuline pour quoi ») :
/// glucides par moment, correction d'hyper (ISF), et ratios post-sport.
struct SousPageRatios: View {
    var body: some View {
        Form {
            SectionRatios()
            SectionRatioCorrection()
            SectionRatiosSport()
        }
        .formStyle(.grouped)
        .navigationTitle("Ratios")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Repas

/// Sous-page « Repas » — horaires de début des sections et réglages de
/// la remontée « Repas à revoir » sur l'accueil.
struct SousPageRepas: View {
    var body: some View {
        Form {
            SectionHorairesRepas()
            SectionRepasARevoirReglages()
        }
        .formStyle(.grouped)
        .navigationTitle("Repas")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Seuils glycémiques

/// Sous-page « Seuils glycémiques » — bornes hypo / hyper personnelles.
struct SousPageSeuils: View {
    var body: some View {
        Form {
            SectionSeuilsGlycemiques()
        }
        .formStyle(.grouped)
        .navigationTitle("Seuils glycémiques")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Données

/// Sous-page « Données » — outils de diagnostic de la source CGM.
struct SousPageDonnees: View {
    var body: some View {
        Form {
            Section {
                NavigationLink("Diagnostic HealthKit") {
                    VueDiagnosticHealthKit()
                }
            } footer: {
                Text("Vérifie ce que l'app reçoit d'Apple Santé (autorisations, dernières glycémies importées).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Données")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Aperçus

#Preview("Ratios") {
    NavigationStack { SousPageRatios() }
        .environment(ProfilService.mockAvecRatiosParMoment())
}

#Preview("Insuline") {
    NavigationStack { SousPageInsuline() }
        .environment(ProfilService.mockComplet())
}

#Preview("Repas") {
    NavigationStack { SousPageRepas() }
        .environment(ProfilService.mockComplet())
}
