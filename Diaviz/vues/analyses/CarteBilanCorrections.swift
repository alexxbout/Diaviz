//
//  CarteBilanCorrections.swift
//  diaviz
//

import SwiftUI

/// Carte sommaire « Corrections » — pousse `PageBilanCorrections`. Même
/// patron que `CarteAnalyseCoucher`/`CarteAnalyseChargeGlycemie` : badge +
/// titre + chevron, puis une ligne glance en dessous — pas un sous-titre
/// sous le titre, qui donnait à cette carte une hauteur différente des deux
/// autres cartes de la page Analyses.
struct CarteBilanCorrections: View {

    /// Bleu système — le bleu roi custom (`0x1A48E8`) était nettement plus
    /// sombre/saturé que l'indigo et l'orange des deux autres cartes
    /// (`Color.indigo`/`Color.orange`, tous deux des couleurs système),
    /// ce qui cassait la cohérence visuelle de la page.
    private static let accent = Color.blue

    let bilan: BilanCorrections

    /// `true` pendant le recalcul — remplace le chevron par un spinner.
    var chargement: Bool = false

    var body: some View {
        NavigationLink {
            ScrollView {
                PageBilanCorrections(bilan: bilan)
                    .padding(16)
            }
            .background(Color(.systemGroupedBackground))
        } label: {
            contenu
        }
        .buttonStyle(.plain)
        .compositingGroup()
        .shadow(color: Self.accent.opacity(0.45), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Corrections. \(sousTitre)")
        .accessibilityHint("Ouvre le bilan des corrections")
        .accessibilityAddTraits(.isButton)
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 14) {
            enTete
            ligneGlance
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte(fond: Self.accent.opacity(0.10))
    }

    private var enTete: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(
                    LinearGradient(
                        colors: [Self.accent, Self.accent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                Image(systemName: "syringe.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            Text("Corrections")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Spacer()

            if chargement {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var ligneGlance: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(Self.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(sousTitre)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
    }

    /// Résumé toutes portées confondues (isolées + au repas) — le détail
    /// par portée vit dans la page, la carte sommaire ne fait qu'annoncer
    /// s'il y a de la matière à consulter.
    private var sousTitre: String {
        guard bilan.nombreTotal > 0 else { return "Pas encore assez de données" }
        let adaptees = bilan.isolees.nombreAdapte + bilan.auRepas.nombreAdapte
        return "\(adaptees) adaptée\(adaptees > 1 ? "s" : "") sur \(bilan.nombreTotal)"
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Corrections — mock") {
    NavigationStack {
        VStack {
            CarteBilanCorrections(bilan: .mock)
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Corrections — vide") {
    NavigationStack {
        VStack {
            CarteBilanCorrections(bilan: .vide)
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
#endif
