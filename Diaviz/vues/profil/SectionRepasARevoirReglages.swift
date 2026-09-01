//
//  SectionRepasARevoirReglages.swift
//  diaviz
//

import SwiftUI

/// Section « REPAS À REVOIR » de la sheet Profil — première section dédiée
/// au réglage d'une fonctionnalité applicative (par opposition aux données
/// personnelles des sections précédentes : ratios, insuline, horaires…).
/// D'autres réglages de ce type rejoindront cette section à l'avenir plutôt
/// que d'être enfouis dans « Préférences avancées ».
struct SectionRepasARevoirReglages: View {

    @Environment(ProfilService.self) private var service

    /// Recharge la vue quand un masquage change ailleurs (long press sur une
    /// carte) — pas de binding direct nécessaire, `RepasARevoirMasquesService`
    /// est `@Observable` et lu dans `body`.
    private var masquesService: RepasARevoirMasquesService { .shared }

    @State private var confirmerSuppression = false

    var body: some View {
        Section {
            Stepper(
                "Occurrences minimales : \(occurrencesMinimales)",
                value: bindingOccurrencesMinimales,
                in: 1...5
            )

            Button("Supprimer les repas masqués", role: .destructive) {
                confirmerSuppression = true
            }
            .disabled(masquesService.idsMasques.isEmpty)
        } header: {
            Text("Repas à revoir")
        } footer: {
            Text("""
            Nombre de fois qu'un même repas doit se reproduire avant \
            d'apparaître dans « Repas à revoir » sur l'accueil — à 1, \
            n'importe quel repas hors cible remonte dès la première fois, \
            sans attendre une récidive. Un repas masqué (appui long sur sa \
            carte) réapparaît automatiquement s'il se reproduit avec un \
            nouveau résultat hors cible.
            """)
        }
        .confirmationDialog(
            "Supprimer les repas masqués ?",
            isPresented: $confirmerSuppression,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                masquesService.toutDemasquer()
            }
        } message: {
            Text("Tous les repas que vous avez masqués réapparaîtront dans « Repas à revoir » s'ils sont toujours hors cible.")
        }
    }

    // MARK: - Binding

    private var occurrencesMinimales: Int {
        service.profil.preferencesAvancees.occurrencesMinimalesRepasARevoir
            ?? CalculRepasARevoir.occurrencesMinimalesParDefaut
    }

    private var bindingOccurrencesMinimales: Binding<Int> {
        Binding(
            get: { occurrencesMinimales },
            set: { nouvelle in
                service.mettreAJour {
                    $0.preferencesAvancees.occurrencesMinimalesRepasARevoir = nouvelle
                }
            }
        )
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    Form {
        SectionRepasARevoirReglages()
    }
    .formStyle(.grouped)
    .environment(ProfilService.mockComplet())
}
#endif
