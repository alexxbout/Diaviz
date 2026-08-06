//
//  SousPagesProfil.swift
//  diaviz
//

import SwiftData
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

/// Sous-page « Données » — outils de diagnostic de la source CGM, et
/// gestion (suppression) des données du hub.
struct SousPageDonnees: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(ProfilService.self) private var profilService

    /// Quel bouton a déclenché le `confirmationDialog` — `nil` quand
    /// aucun n'est actif. Un seul dialog partagé plutôt que deux `@State
    /// Bool` : évite toute ambiguïté si les deux boutons étaient tapés
    /// coup sur coup.
    @State private var suppressionEnCours: TypeSuppression?

    var body: some View {
        Form {
            Section {
                NavigationLink("Diagnostic HealthKit") {
                    VueDiagnosticHealthKit()
                }
            } footer: {
                Text("Vérifie ce que l'app reçoit d'Apple Santé (autorisations, dernières glycémies importées).")
            }

            Section {
                Button("Supprimer les données", role: .destructive) {
                    suppressionEnCours = .donneesSeules
                }
                Button("Supprimer les données et réglages", role: .destructive) {
                    suppressionEnCours = .donneesEtReglages
                }
            } header: {
                Text("Gestion des données")
            } footer: {
                Text("Les glycémies (CGM) importées d'Apple Santé ne sont jamais supprimées — seules les données saisies dans l'app (repas, injections, sport, resucrages…) le sont.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Données")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            Text(titreConfirmation),
            isPresented: Binding(
                get: { suppressionEnCours != nil },
                set: { if !$0 { suppressionEnCours = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                guard let cible = suppressionEnCours else { return }
                supprimer(cible)
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text(messageConfirmation)
        }
    }

    private var titreConfirmation: String {
        switch suppressionEnCours {
        case .donneesSeules: "Supprimer les données ?"
        case .donneesEtReglages: "Supprimer les données et réglages ?"
        case nil: ""
        }
    }

    private var messageConfirmation: String {
        switch suppressionEnCours {
        case .donneesSeules:
            "Repas, injections, activités sportives, resucrages, états et médications seront définitivement supprimés. Les glycémies et vos réglages de profil sont conservés. Action irréversible."
        case .donneesEtReglages:
            "Repas, injections, activités sportives, resucrages, états et médications seront définitivement supprimés, et votre profil (insuline, ratios, seuils…) sera réinitialisé. Les glycémies sont conservées. Action irréversible."
        case nil:
            ""
        }
    }

    /// Supprime en bloc les entités du hub autres que `GlucoseReading`
    /// (jamais concerné — c'est la donnée source, non ressaisissable).
    /// `context.delete(model:)` est un delete batch SwiftData, pas besoin
    /// de fetch préalable.
    private func supprimer(_ cible: TypeSuppression) {
        try? modelContext.delete(model: Injection.self)
        try? modelContext.delete(model: Repas.self)
        try? modelContext.delete(model: Aliment.self)
        try? modelContext.delete(model: ActiviteSportive.self)
        try? modelContext.delete(model: EtatDeclare.self)
        try? modelContext.delete(model: Medicament.self)
        try? modelContext.delete(model: PeriodePause.self)
        try? modelContext.delete(model: Resucrage.self)

        if cible == .donneesEtReglages {
            profilService.reinitialiser()
        }
    }

    private enum TypeSuppression {
        case donneesSeules
        case donneesEtReglages
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
