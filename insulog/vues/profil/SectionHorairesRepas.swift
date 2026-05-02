//
//  SectionHorairesRepas.swift
//  insulog
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « HORAIRES DES REPAS » — quatre `DatePicker` compacts en
/// `.hourAndMinute` pour les horaires habituels du petit-déjeuner,
/// déjeuner, goûter et dîner.
///
/// Forcés en `Locale("fr_FR")` pour garantir le format 24h
/// indépendamment des préférences système — un build de l'utilisateur
/// francophone qui lirait par accident le format AM/PM serait pénible.
struct SectionHorairesRepas: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Section {
            ligne("Petit-déjeuner", binding: bindingHoraire(\.petitDejeuner))
            ligne("Déjeuner",       binding: bindingHoraire(\.dejeuner))
            ligne("Goûter",         binding: bindingHoraire(\.gouter))
            ligne("Dîner",          binding: bindingHoraire(\.diner))
        } header: {
            Text("Horaires des repas")
        } footer: {
            Text("""
            Permet de catégoriser automatiquement vos repas selon \
            l'heure de saisie.
            """)
        }
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }

    // MARK: - Helpers

    private func ligne(_ libelle: String, binding: Binding<Date>) -> some View {
        DatePicker(
            libelle,
            selection: binding,
            displayedComponents: [.hourAndMinute]
        )
    }

    /// Binding paramétré par keyPath sur `HorairesRepas` — comme pour
    /// `SectionRatios`, évite de répéter quatre bindings.
    private func bindingHoraire(
        _ keyPath: WritableKeyPath<HorairesRepas, Date>
    ) -> Binding<Date> {
        Binding(
            get: { service.profil.horairesRepas[keyPath: keyPath] },
            set: { nouvelle in
                service.mettreAJour { profil in
                    profil.horairesRepas[keyPath: keyPath] = nouvelle
                }
            }
        )
    }
}
