//
//  CarteChargeActivite.swift
//  diaviz
//

import SwiftUI

/// Carte accueil « Charge d'activité » — écart de la semaine vs la normale
/// personnelle, mini-sparkline 7 jours. **Même patron exact** que
/// `CarteGlucidesSemaine` (icône+titre teintés, gros chiffre+sous-titre,
/// sparkline à droite, chevron) : chrome identique, pas une variante.
///
/// Fond plat, pas de verre — rien ne défile derrière cette carte, le
/// matériau Liquid Glass n'a de sens que sur un calque de navigation/contrôle
/// qui flotte au-dessus d'un contenu qui bouge.
///
/// Couleur des barres de la sparkline **neutre** — la tendance (hausse/
/// baisse) est un jugement sur l'**agrégat** de plusieurs jours
/// (`CalculChargeContinue`), jamais un calcul par jour : comparer un jour
/// isolé à une moyenne journalière, que le sport ne respecte jamais par
/// nature, faisait ressortir un jour de repos ordinaire en rouge au milieu
/// d'une semaine par ailleurs normale.
struct CarteChargeActivite: View {

    let synthese: SyntheseChargeContinue
    let onTap: () -> Void

    fileprivate static let teinte = Color.orange

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                ligneTitre
                ligneContenu
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
            .overlay(NiveauCarte.carte.forme.strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
            .contentShape(NiveauCarte.carte.forme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelleAccessibilite)
        .accessibilityHint("Ouvre le détail de la charge d'activité sur 14 jours")
    }

    private var ligneTitre: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinte)
            Text("Charge d'activité")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinte)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    private var ligneContenu: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if let ecart = synthese.ecartRelatif {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(ecartFormate(ecart))
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text("vs normale")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Pas assez de recul")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Text(libelleTendance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            SparklineCharge(serie: Array(synthese.serieJournaliere.suffix(7)), teinte: Self.teinte)
                .accessibilityHidden(true)
        }
    }

    /// Signe explicite (« +12 % » / « −22 % »), même convention que les
    /// deltas glucides — un écart relatif se lit toujours signé.
    private func ecartFormate(_ ecart: Double) -> String {
        let pct = Int((ecart * 100).rounded())
        let signe = pct > 0 ? "+" : (pct < 0 ? "\u{2212}" : "")
        return "\(signe)\(abs(pct))%"
    }

    private var libelleTendance: String {
        switch synthese.tendance {
        case .enBaisse(let jours): return "en baisse depuis \(jours) j"
        case .enHausse(let jours): return "en hausse depuis \(jours) j"
        case .stable: return "stable vs votre normale"
        }
    }

    private var libelleAccessibilite: String {
        let base = synthese.ecartRelatif.map { "Charge d'activité, \(ecartFormate($0)) vs votre normale" }
            ?? "Charge d'activité, pas assez de recul"
        return "\(base), \(libelleTendance)"
    }
}

// MARK: - Sparkline

/// Mini histogramme 7 barres — même composant que `SparklineGlucides`
/// (`CarteGlucidesSemaine`) : hauteur proportionnelle au maximum de la
/// série affichée, dernier jour (aujourd'hui) en teinte pleine.
private struct SparklineCharge: View {
    let serie: [PointChargeJour]
    let teinte: Color

    private static let largeurBarre: CGFloat = 5
    private static let spacing: CGFloat = 4

    private var maximum: Double {
        max(serie.map(\.score).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            ForEach(Array(serie.enumerated()), id: \.offset) { index, point in
                let estAujourdhui = index == serie.count - 1
                GeometryReader { geo in
                    let fraction = max(0.03, point.score / maximum)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(teinte.opacity(estAujourdhui ? 1 : 0.5))
                            .frame(height: geo.size.height * fraction)
                    }
                }
                .frame(width: Self.largeurBarre)
            }
        }
        .frame(width: 64, height: 44)
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Charge en baisse") {
    CarteChargeActivite(synthese: .mockBaisse, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Sombre") {
    CarteChargeActivite(synthese: .mockBaisse, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
#endif
