//
//  SectionSeuilsGlycemiques.swift
//  insulog
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « SEUILS GLYCÉMIQUES » — bornes basse (hypo) et haute
/// (hyper) en mg/dL.
///
/// Valeurs par défaut : 70 / 180 mg/dL (recommandations TIR
/// standards). Affichage coloré (rouge / orange) pour rendre la
/// sémantique visible d'un coup d'œil — la couleur est purement
/// cosmétique et n'a pas de signification clinique.
struct SectionSeuilsGlycemiques: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Section {
            ligneSeuil(
                libelle: "Hypoglycémie",
                binding: bindingHypo,
                couleur: .red,
                plage: 50...80,
                pas: 5
            )
            ligneSeuil(
                libelle: "Hyperglycémie",
                binding: bindingHyper,
                couleur: .orange,
                plage: 140...250,
                pas: 10
            )
        } header: {
            Text("Seuils glycémiques")
        } footer: {
            Text("""
            Ces seuils sont utilisés pour catégoriser vos glycémies \
            dans les analyses (zone cible, hypos, hypers).
            """)
        }
    }

    // MARK: - Ligne générique

    private func ligneSeuil(
        libelle: String,
        binding: Binding<Double>,
        couleur: Color,
        plage: ClosedRange<Double>,
        pas: Double
    ) -> some View {
        HStack {
            Text(libelle)
            Spacer()
            Text("\(Int(binding.wrappedValue)) mg/dL")
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(couleur)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: binding.wrappedValue)
            Stepper("", value: binding, in: plage, step: pas)
                .labelsHidden()
        }
    }

    // MARK: - Bindings

    private var bindingHypo: Binding<Double> {
        Binding(
            get: { service.profil.seuilsGlycemiques.hypoglycemie },
            set: { nouveau in
                service.mettreAJour { $0.seuilsGlycemiques.hypoglycemie = nouveau }
            }
        )
    }

    private var bindingHyper: Binding<Double> {
        Binding(
            get: { service.profil.seuilsGlycemiques.hyperglycemie },
            set: { nouveau in
                service.mettreAJour { $0.seuilsGlycemiques.hyperglycemie = nouveau }
            }
        )
    }
}
