//
//  ProfilVue.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Vue racine de la sheet Profil — **index** vers cinq sous-pages
/// thématiques (Insuline, Ratios, Repas, Seuils, Données), chacune
/// résumant sa configuration courante en sous-titre.
///
/// Remplace l'ancien empilement de huit sections dans un seul `Form`
/// scrollable : on voit l'essentiel d'un coup d'œil sans dérouler, et
/// chaque réglage vit dans un contexte lisible.
///
/// Pas de bouton « Enregistrer » : chaque modification déclenche une
/// sauvegarde immédiate via `ProfilService.mettreAJour(_:)`. La sheet
/// se ferme avec « Fermer » (topBarTrailing) ; si des champs requis
/// sont invalides au moment de la fermeture, on prévient l'utilisateur
/// par une `Alert` — mais on n'empêche jamais la sortie.
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

    /// Drapeau de revisite volontaire de l'onboarding — indépendant du
    /// `fullScreenCover` de premier lancement dans `AppTabVues` (celui-là
    /// se déclenche sur profil invalide, celui-ci sur demande explicite).
    @State private var afficherOnboarding: Bool = false

    var body: some View {
        Form {
            SectionPhotoProfil()
            SectionInformationsBase()

            Section {
                lien(
                    "Insuline",
                    icone: "drop.fill",
                    couleur: .blue,
                    resume: resumeInsuline
                ) { SousPageInsuline() }

                lien(
                    "Ratios",
                    icone: "function",
                    couleur: .indigo,
                    resume: resumeRatios
                ) { SousPageRatios() }

                lien(
                    "Repas",
                    icone: "fork.knife",
                    couleur: .green,
                    resume: resumeRepas
                ) { SousPageRepas() }

                lien(
                    "Resucrage",
                    icone: "cross.case.fill",
                    couleur: .orange,
                    resume: "Carte accueil, ajout rapide"
                ) { SousPageResucrage() }

                lien(
                    "Analyse du coucher",
                    icone: "moon.stars.fill",
                    couleur: .purple,
                    resume: resumeAnalyseCoucher
                ) { SousPageAnalyseCoucher() }

                lien(
                    "Seuils glycémiques",
                    icone: "chart.line.uptrend.xyaxis",
                    couleur: .red,
                    resume: resumeSeuils
                ) { SousPageSeuils() }

                lien(
                    "Données",
                    icone: "externaldrive.fill",
                    couleur: .secondary,
                    resume: "Diagnostic HealthKit"
                ) { SousPageDonnees() }
            }

            // Documentation, volontairement à part des réglages comme de
            // l'onglet Analyses : ces fiches ne connaissent aucune de vos
            // données et ne doivent jamais en croiser.
            Section {
                lien(
                    "Bibliothèque",
                    icone: "books.vertical.fill",
                    couleur: .brown,
                    resume: "Ce que dit la littérature scientifique"
                ) { EncyclopedieVue() }
            }

            Section {
                Button {
                    afficherOnboarding = true
                } label: {
                    Label("Revoir la configuration initiale", systemImage: "arrow.counterclockwise")
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
        .fullScreenCover(isPresented: $afficherOnboarding) {
            OnboardingVue()
                .environment(service)
        }
    }

    // MARK: - Row de navigation

    /// Row d'index : icône teintée, titre, et **résumé de la config
    /// courante** en sous-titre — c'est ce résumé qui évite d'avoir à
    /// entrer dans chaque sous-page pour savoir ce qui y est réglé.
    private func lien<Destination: View>(
        _ titre: String,
        icone: String,
        couleur: Color,
        resume: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(couleur)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titre)
                        .font(.body)
                    Text(resume)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityLabel("\(titre). \(resume)")
    }

    // MARK: - Résumés de configuration

    private var resumeInsuline: String {
        let p = service.profil
        let dia = formateHeures(p.dureeActionInsulineHeures)
        let intervalle = formateHeures(p.intervalleMinimumLenteEffectif)
        return "\(p.insulineRapide.rawValue) · \(p.insulineLente.rawValue) · \(dia) · \(intervalle)"
    }

    private var resumeRatios: String {
        let p = service.profil
        var morceaux: [String] = [p.modeRatio == .unique ? "Ratio unique" : "Par moment"]
        if let isf = p.ratioCorrection {
            morceaux.append("ISF \(Int(isf))")
        }
        if p.ratiosSportEffectifs.aAuMoinsUnRatio {
            morceaux.append("sport")
        }
        return morceaux.joined(separator: " · ")
    }

    private var resumeAnalyseCoucher: String {
        let seuil = service.profil.preferencesAvancees.seuilRepasCopieuxNuit
            ?? ConfigBasale.seuilRepasCopieuxParDefaut
        return "Dîner copieux ≥ \(seuil) g"
    }

    private var resumeRepas: String {
        let occurrences = service.profil.preferencesAvancees.occurrencesMinimalesRepasARevoir
        let horaires = "4 sections"
        guard let occurrences else { return "\(horaires) · repas à revoir" }
        return "\(horaires) · à revoir dès \(occurrences)×"
    }

    private var resumeSeuils: String {
        let s = service.profil.seuilsGlycemiques
        return "\(Int(s.hypoglycemie)) – \(Int(s.hyperglycemie)) mg/dL"
    }

    /// Format court d'une durée en heures — « 3h », « 22h30 ».
    private func formateHeures(_ valeur: Double) -> String {
        let h = Int(valeur)
        let m = Int((valeur - Double(h)) * 60)
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
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

#if DEBUG
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
#endif
