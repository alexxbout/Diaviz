//
//  SectionRatiosRepas.swift
//  diaviz
//

import SwiftUI

/// Ratio effectif du repas face au ratio configuré, côte à côte, au-dessus des
/// alertes. Sans couleur : le verdict appartient à la carte de validation.
///
/// Le ratio effectif compte l'ajustement (insuline réellement mise pour ces
/// glucides) mais pas la correction, qui répond à la glycémie du moment.
struct SectionRatiosRepas: View {

    let glucides: Double
    /// Dose de base + ajustements, hors correction.
    let doseCouvrante: Double
    let avecAjustement: Bool
    /// Ratio en vigueur, `nil` si aucun n'est réglé pour ce moment.
    let ratioConfigure: ProfilRatio?

    var body: some View {
        Section {
            HStack(spacing: 0) {
                colonne(
                    titre: "Ratio effectif",
                    valeur: doseCouvrante > 0 ? Self.ratio(glucides / doseCouvrante) : "—",
                    precision: doseCouvrante <= 0 ? "aucune dose" : avecAjustement ? "ajustement inclus" : "ce repas"
                )
                Divider()
                colonne(
                    titre: "Ratio configuré",
                    valeur: ratioConfigure.map { Self.ratio($0.grammesParUnite) } ?? "—",
                    precision: ratioConfigure?.libelle ?? "non réglé"
                )
            }
        }
    }

    private func colonne(titre: String, valeur: String, precision: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(valeur)
                .font(.title3.bold())
                .monospacedDigit()
            Text(precision)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private static func ratio(_ grammesParUnite: Double) -> String {
        "1 u / \(grammesParUnite.formatted(.number.precision(.fractionLength(0...1)))) g"
    }
}

#if DEBUG
#Preview {
    Form {
        SectionRatiosRepas(
            glucides: 21.5, doseCouvrante: 0.5, avecAjustement: true,
            ratioConfigure: ProfilRatio(grammesParUnite: 10, libelle: "déjeuner")
        )
        SectionRatiosRepas(glucides: 40, doseCouvrante: 0, avecAjustement: false, ratioConfigure: nil)
    }
    .formStyle(.grouped)
}
#endif
