//
//  PageChargeActivite.swift
//  diaviz
//

import Charts
import SwiftUI

/// Page de détail « Charge d'activité » — pushée depuis `CarteChargeActivite`.
/// Écart + tendance en tête, histogramme des 14 derniers jours (7 « semaine
/// dernière » en teinte atténuée, 7 « cette semaine » en teinte pleine) —
/// même structure que `PageGlucides`.
///
/// Reste volontairement simple : une seule page, un seul graphique, aucune
/// interaction de sélection — la carte accueil donne déjà l'essentiel, cette
/// page ne fait qu'étaler la série sous-jacente.
struct PageChargeActivite: View {

    let synthese: SyntheseChargeContinue

    private let teinte = Color.orange

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnTeteAnalyse(
                    surtitre: "Sport",
                    titre: "Charge d'activité",
                    accroche: "Votre charge sportive des 7 derniers jours, comparée à votre normale des 4 dernières semaines.",
                    ambiance: .chargeActivite
                )
                enTeteStats
                graphique
                Label(
                    "14 derniers jours. Charge = durée × intensité de chaque séance, sommée par jour.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Charge d'activité")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var enTeteStats: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Hero = le niveau en mot (basse/normale/haute), pas l'écart
            // brut — même principe que la carte accueil.
            Text(niveau.libelle)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(niveau.couleur)
            Text(ligneDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private var graphique: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                legendePastille(couleur: teinte.opacity(0.35), texte: "Il y a 8-14 jours")
                legendePastille(couleur: teinte, texte: "7 derniers jours")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Chart {
                ForEach(Array(synthese.serieJournaliere.enumerated()), id: \.offset) { index, point in
                    BarMark(
                        x: .value("Jour", point.jour, unit: .day),
                        y: .value("Charge", point.score)
                    )
                    .foregroundStyle(index >= 7 ? teinte : teinte.opacity(0.35))
                    .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private func legendePastille(couleur: Color, texte: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(couleur).frame(width: 7, height: 7)
            Text(texte)
        }
    }

    private func ecartFormate(_ ecart: Double) -> String {
        let pct = Int((ecart * 100).rounded())
        let signe = pct > 0 ? "+" : (pct < 0 ? "\u{2212}" : "")
        return "\(signe)\(abs(pct))%"
    }

    private enum Niveau {
        case basse, normale, haute, inconnue

        var libelle: String {
            switch self {
            case .basse:    return "Charge basse"
            case .normale:  return "Charge normale"
            case .haute:    return "Charge haute"
            case .inconnue: return "Pas assez de recul"
            }
        }

        var couleur: Color {
            switch self {
            case .basse:    return .red
            case .haute:    return .blue
            case .normale, .inconnue: return .primary
            }
        }
    }

    private var niveau: Niveau {
        guard let ecart = synthese.ecartRelatif else { return .inconnue }
        if ecart <= -CalculChargeContinue.seuilEcartTendance { return .basse }
        if ecart >= CalculChargeContinue.seuilEcartTendance { return .haute }
        return .normale
    }

    /// « −22 % vs votre normale · en baisse depuis 5 jours » — écart et
    /// tendance fusionnés en une ligne, plus de sous-titre redondant.
    private var ligneDetail: String {
        let ecartTexte = synthese.ecartRelatif.map { "\(ecartFormate($0)) vs votre normale" }
        switch synthese.tendance {
        case .enBaisse(let jours):
            return [ecartTexte, "en baisse depuis \(jours) jours"].compactMap { $0 }.joined(separator: " · ")
        case .enHausse(let jours):
            return [ecartTexte, "en hausse depuis \(jours) jours"].compactMap { $0 }.joined(separator: " · ")
        case .stable:
            return ecartTexte ?? "pas d'activité récente sur 4 semaines"
        }
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    NavigationStack {
        PageChargeActivite(synthese: .mockBaisse)
    }
}

#Preview("Sombre") {
    NavigationStack {
        PageChargeActivite(synthese: .mockBaisse)
    }
    .preferredColorScheme(.dark)
}
#endif
