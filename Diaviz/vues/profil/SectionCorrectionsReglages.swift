//
//  SectionCorrectionsReglages.swift
//  diaviz
//

import SwiftUI

/// Section « CORRECTIONS » de la sheet Profil — réglages du bilan des
/// corrections (page Analyses). Même famille que `SectionAnalyseCoucherReglages`
/// et `SectionRepasARevoirReglages` : un réglage applicatif, pas une donnée
/// personnelle.
struct SectionCorrectionsReglages: View {

    @Environment(ProfilService.self) private var service

    private let pas = 5

    var body: some View {
        Section {
            Stepper(
                "Fenêtre repas : ± \(fenetreMinutes) min",
                value: bindingFenetre,
                in: 10...60,
                step: pas
            )
        } header: {
            Text("Corrections")
        } footer: {
            Text("""
            Une correction prise à moins de ce délai d'un repas voit sa \
            courbe CGM portée à la fois par l'insuline et par les glucides — \
            la juger « adaptée » ou « sur-correction » mélangerait les deux \
            effets. Le bilan des corrections les distingue des corrections \
            isolées plutôt que de les exclure ou de les mêler.
            """)
        }
    }

    // MARK: - Binding

    private var fenetreMinutes: Int {
        service.profil.preferencesAvancees.fenetreRepasCorrectionMinutes
            ?? Int(CalculBilanCorrections.fenetreRepasMinutesParDefaut)
    }

    private var bindingFenetre: Binding<Int> {
        Binding(
            get: { fenetreMinutes },
            set: { nouvelle in
                service.mettreAJour {
                    $0.preferencesAvancees.fenetreRepasCorrectionMinutes = nouvelle
                }
            }
        )
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    Form {
        SectionCorrectionsReglages()
    }
    .formStyle(.grouped)
    .environment(ProfilService.mockComplet())
}
#endif
