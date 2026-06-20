//
//  ProfilVue.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Vue racine de la sheet Profil — héberge les sept sections de
/// réglages dans un `Form` natif `.grouped`.
///
/// Pas de bouton « Enregistrer » : chaque modification déclenche une
/// sauvegarde immédiate via `ProfilService.mettreAJour(_:)`. La sheet
/// se ferme avec « Fermer » (topBarTrailing) ; si des champs requis
/// sont invalides au moment de la fermeture, on prévient l'utilisateur
/// par une `Alert` — mais on n'empêche jamais la sortie. La validation
/// finale aura lieu au prochain démarrage de l'app (à câbler plus tard).
///
/// Le service est injecté via `@Environment(ProfilService.self)` —
/// c'est ce qui permet aux previews d'utiliser leur propre mock isolé
/// (`mockComplet()`, `mockVide()`, etc.).
struct ProfilVue: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(ProfilService.self) private var service

    /// Drapeau d'affichage de l'alerte « Profil incomplet » — montrée
    /// uniquement si l'utilisateur tente de fermer alors qu'il manque
    /// des champs requis. Donne le choix entre revenir au formulaire
    /// et fermer quand même.
    @State private var afficherAlerteIncomplet: Bool = false

    var body: some View {
        Form {
            SectionInformationsBase()
            SectionInsuline()
            SectionRatios()
            SectionRatioCorrection()
            SectionHorairesRepas()
            SectionSeuilsGlycemiques()
            SectionPreferencesAvancees()
            Section("Données") {
                NavigationLink("Diagnostic HealthKit") {
                    VueDiagnosticHealthKit()
                }
            }
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fermer") { tenterFermeture() }
                    .fontWeight(.semibold)
            }
        }
        .alert(
            "Profil incomplet",
            isPresented: $afficherAlerteIncomplet
        ) {
            Button("Continuer la saisie", role: .cancel) { }
            Button("Fermer quand même") { dismiss() }
        } message: {
            Text("""
            Certains champs requis ne sont pas renseignés. Vous \
            pouvez les compléter maintenant ou plus tard.
            """)
        }
    }

    /// Logique de fermeture : on ferme directement si le profil est
    /// valide ; sinon on demande confirmation. Il n'y a pas de
    /// « modifications non enregistrées » à proprement parler — chaque
    /// frappe est déjà persistée — mais le profil incomplet vaut
    /// presque la même chose côté UX.
    private func tenterFermeture() {
        if service.profil.estValide {
            dismiss()
        } else {
            afficherAlerteIncomplet = true
        }
    }
}

// MARK: - Aperçus

#Preview("Profil complet") {
    NavigationStack {
        ProfilVue()
    }
    .environment(ProfilService.mockComplet())
}

#Preview("Profil avec ratios différents") {
    NavigationStack {
        ProfilVue()
    }
    .environment(ProfilService.mockAvecRatiosParMoment())
}

#Preview("Profil neuf - champs vides") {
    NavigationStack {
        ProfilVue()
    }
    .environment(ProfilService.mockVide())
}
