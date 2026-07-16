//
//  SectionHorairesRepas.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « HORAIRES DES REPAS » — quatre `DatePicker` compacts en
/// `.hourAndMinute` pour les heures de **début** du petit-déjeuner,
/// déjeuner, goûter et dîner.
///
/// Ces heures sont des **bornes de début**, pas des points de référence :
/// un repas est classé dans la section dont le début est le dernier
/// atteint avant son heure. La fenêtre entre la fin du dîner (+3h fixe,
/// non réglable) et le début du petit-déjeuner forme automatiquement une
/// 5ᵉ section « Nuit », pour ne pas classer à tort un repas de milieu de
/// nuit dans « Dîner ».
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
            Heure de **début** de chaque section — un repas saisi est classé \
            dans la dernière section commencée avant son heure. La nuit \
            (entre la fin du dîner et le petit-déjeuner) forme sa propre \
            section automatiquement.
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
