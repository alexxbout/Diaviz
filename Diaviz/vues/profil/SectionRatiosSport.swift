//
//  SectionRatiosSport.swift
//  diaviz
//

import SwiftUI

/// Section « Après une activité sportive » — un ratio glucides/insuline
/// par type de sport, appliqué aux repas qui suivent une séance dans la
/// fenêtre d'effet.
///
/// Ratio **absolu** (« 1u / 14g ») et non pourcentage de réduction : c'est
/// la même unité que les ratios par moment juste au-dessus, donc lisible
/// sans conversion mentale. `nil` (affiché « Aucun ») = pas de ratio
/// spécifique, on retombe sur le ratio du moment.
struct SectionRatiosSport: View {

    @Environment(ProfilService.self) private var service

    private var ratios: RatiosSport { service.profil.ratiosSportEffectifs }

    var body: some View {
        Section {
            ForEach(TypeSport.allCases, id: \.self) { type in
                ligneSport(type)
            }
        } header: {
            Text("Après une activité sportive")
        } footer: {
            Text("""
            Ratio appliqué aux repas suivant une séance. « Aucun » = on \
            garde le ratio du moment. Ces valeurs servent de référence \
            d'analyse — l'app ne calcule pas vos doses.
            """)
        }

        Section {
            fenetreEffet
        } footer: {
            Text("Durée après la séance pendant laquelle le ratio sport s'applique.")
        }
    }

    // MARK: - Lignes

    private func ligneSport(_ type: TypeSport) -> some View {
        let valeur = ratios.ratio(pour: type)
        return HStack(spacing: 12) {
            Image(systemName: type.icone)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(type.rawValue)
                .font(.body)

            Spacer(minLength: 8)

            if let valeur {
                Text("1u / \(formate(valeur))g")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: valeur)
            } else {
                Text("Aucun")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                BoutonStepper(systemImage: "minus") { decrementer(type) }
                    .disabled(valeur == nil)
                BoutonStepper(systemImage: "plus") { incrementer(type) }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            valeur.map { "\(type.rawValue) : 1 unité pour \(formate($0)) grammes" }
                ?? "\(type.rawValue) : aucun ratio spécifique"
        )
    }

    private var fenetreEffet: some View {
        let heures = ratios.fenetreEffetHeures
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fenêtre d'effet")
                Spacer()
                Text(formateHeures(heures))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: heures)
            }

            Slider(value: bindingFenetre, in: 1...12, step: 0.5)

            HStack {
                Text("1h")
                Spacer()
                Text("3h (standard)")
                Spacer()
                Text("12h")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Édition

    /// Premier incrément depuis « Aucun » : on part du ratio du moment le
    /// plus courant plutôt que de 0 — l'utilisateur ajuste à la marge au
    /// lieu de remonter depuis rien.
    private func incrementer(_ type: TypeSport) {
        let courant = ratios.ratio(pour: type) ?? ratioDeBase
        maj { $0.definir(min(60, courant + 1), pour: type) }
    }

    /// Sous 1g le ratio n'a plus de sens : on repasse à « Aucun ».
    private func decrementer(_ type: TypeSport) {
        guard let courant = ratios.ratio(pour: type) else { return }
        let nouveau = courant - 1
        maj { $0.definir(nouveau < 1 ? nil : nouveau, pour: type) }
    }

    private var bindingFenetre: Binding<Double> {
        Binding(
            get: { ratios.fenetreEffetHeures },
            set: { nouveau in maj { $0.fenetreEffetHeures = nouveau } }
        )
    }

    private func maj(_ transformation: (inout RatiosSport) -> Void) {
        var copie = ratios
        transformation(&copie)
        service.mettreAJour { $0.ratiosSport = copie }
    }

    /// Ratio de départ proposé au premier réglage d'un sport — le ratio
    /// unique s'il est défini, sinon celui du déjeuner, sinon 10g.
    private var ratioDeBase: Double {
        let profil = service.profil
        return profil.ratioUnique
            ?? profil.ratiosParMoment.dejeuner
            ?? 10
    }

    // MARK: - Formatage

    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }

    private func formateHeures(_ valeur: Double) -> String {
        let h = Int(valeur)
        let m = Int((valeur - Double(h)) * 60)
        return m == 0 ? "\(h) h" : "\(h)h\(String(format: "%02d", m))"
    }
}

// MARK: - Aperçu

#Preview {
    NavigationStack {
        Form {
            SectionRatiosSport()
        }
        .formStyle(.grouped)
    }
    .environment(ProfilService.mockComplet())
}
