//
//  CarteBilanCorrections.swift
//  diaviz
//

import SwiftUI

/// Carte sommaire « Corrections » — pousse `PageBilanCorrections`. Traitement
/// plus léger que `CarteAnalyseCoucher` (pas de lignes glance par sous-
/// analyse) : une seule analyse ici, la sous-ligne suffit à résumer l'état.
struct CarteBilanCorrections: View {

    /// Bleu roi profond — même accent que le halo de l'ambiance
    /// `EnTeteAnalyse.corrections`.
    private static let accent = Color(red: 0x1A / 255, green: 0x48 / 255, blue: 0xE8 / 255)

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

            VStack(alignment: .leading, spacing: 2) {
                Text("Corrections")
                    .font(.title3.bold())
                Text(sousTitre)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if chargement {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte(fond: Self.accent.opacity(0.10))
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
