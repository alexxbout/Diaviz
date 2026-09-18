//
//  SectionAnalyseCoucherReglages.swift
//  diaviz
//

import SwiftUI

/// Section « ANALYSE DU COUCHER » de la sheet Profil — réglages de l'analyse
/// basale (B1). Même famille que `SectionRepasARevoirReglages` : un réglage
/// applicatif, pas une donnée personnelle.
struct SectionAnalyseCoucherReglages: View {

    @Environment(ProfilService.self) private var service

    /// Pas du stepper — 10 g, l'ordre de grandeur d'une portion.
    private let pas = 10

    var body: some View {
        Section {
            Stepper(
                "Dîner copieux à partir de : \(seuilRepasCopieux) g",
                value: bindingSeuil,
                in: ConfigBasale.plageSeuilRepasCopieux,
                step: pas
            )
        } header: {
            Text("Analyse du coucher")
        } footer: {
            Text("""
            Un dîner très glucidique s'assimile tard : la glycémie est belle \
            au coucher puis monte en pleine nuit. L'analyse de la basale \
            écarte les nuits précédées d'un tel repas, parce qu'elle y \
            lirait une basale trop faible alors qu'il s'agit de digestion. \
            Plus le seuil est bas, plus de nuits sont écartées — et plus les \
            verdicts restants sont fiables.
            """)
        }

        Section {
            Toggle("Stades de sommeil sur la courbe", isOn: bindingOverlaySommeil)
        } footer: {
            Text("""
            Superpose les stades de sommeil enregistrés par ta Watch (ou une \
            autre source Santé) sur la courbe de la vue « Par nuit ». Absent \
            les nuits sans donnée de sommeil — jamais de bande approximative.
            """)
        }
    }

    // MARK: - Binding

    private var seuilRepasCopieux: Int {
        service.profil.preferencesAvancees.seuilRepasCopieuxNuit
            ?? ConfigBasale.seuilRepasCopieuxParDefaut
    }

    private var bindingSeuil: Binding<Int> {
        Binding(
            get: { seuilRepasCopieux },
            set: { nouveau in
                service.mettreAJour {
                    $0.preferencesAvancees.seuilRepasCopieuxNuit = nouveau
                }
            }
        )
    }

    private var bindingOverlaySommeil: Binding<Bool> {
        Binding(
            get: { service.profil.preferencesAvancees.overlaySommeilActive ?? true },
            set: { nouveau in
                service.mettreAJour {
                    $0.preferencesAvancees.overlaySommeilActive = nouveau
                }
            }
        )
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    Form {
        SectionAnalyseCoucherReglages()
    }
    .formStyle(.grouped)
    .environment(ProfilService.mockComplet())
}
#endif
