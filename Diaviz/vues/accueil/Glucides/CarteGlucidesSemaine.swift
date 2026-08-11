//
//  CarteGlucidesSemaine.swift
//  diaviz
//

import SwiftUI

/// Carte accueil « Glucides » — moyenne quotidienne de la semaine en cours,
/// delta vs la semaine précédente, mini-sparkline 7 jours. Même langage
/// visuel que `CarteScoreQuotidien` (icône+titre+chevron, contenu+mini-graphe),
/// poussée vers `PageGlucides` au tap.
///
/// Purement descriptive — aucune tranche jugée bonne ou mauvaise : manger
/// plus ou moins de glucides n'est ni un succès ni un échec, contrairement au
/// score glycémique (voir CLAUDE.md, « pas de recommandations, seulement des
/// observations »).
struct CarteGlucidesSemaine: View {

    let synthese: SyntheseGlucidesHebdo
    let onTap: () -> Void

    fileprivate static let teinte = Color.brown

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
        .accessibilityHint("Ouvre le détail des glucides sur 14 jours")
    }

    private var ligneTitre: some View {
        HStack(spacing: 6) {
            Image(systemName: "carrot.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinte)
            Text("Glucides")
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
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(synthese.moyenneCetteSemaine.rounded()))")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("g / j")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(synthese.libelleDelta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            SparklineGlucides(serie: Array(synthese.serieJournaliere.suffix(7)), teinte: Self.teinte)
                .accessibilityHidden(true)
        }
    }

    private var libelleAccessibilite: String {
        "Glucides, \(Int(synthese.moyenneCetteSemaine.rounded())) grammes par jour en moyenne cette semaine, \(synthese.libelleDelta)"
    }
}

// MARK: - Formatage partagé

extension SyntheseGlucidesHebdo {

    /// Delta factuel entre les deux moyennes, sans jugement de valeur — signe
    /// typographique, même convention que `Double.ecartDoseFormate`.
    var libelleDelta: String {
        let delta = Int((moyenneCetteSemaine - moyenneSemaineDerniere).rounded())
        let derniere = Int(moyenneSemaineDerniere.rounded())
        if delta == 0 { return "stable vs semaine dernière (\(derniere) g/j)" }
        let signe = delta > 0 ? "+" : "\u{2212}"
        return "\(signe)\(abs(delta)) g vs semaine dernière (\(derniere) g/j)"
    }
}

// MARK: - Sparkline

/// Mini histogramme 7 barres, composé à la main comme `BarresHistorique`
/// (`CarteScoreQuotidien`) — hauteur proportionnelle au maximum de la série
/// affichée, dernier jour (aujourd'hui) en teinte pleine.
private struct SparklineGlucides: View {
    let serie: [PointGlucidesJour]
    let teinte: Color

    private static let largeurBarre: CGFloat = 5
    private static let spacing: CGFloat = 4

    private var maximum: Int {
        max(serie.map(\.totalGlucides).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            ForEach(Array(serie.enumerated()), id: \.offset) { index, point in
                let estAujourdhui = index == serie.count - 1
                GeometryReader { geo in
                    let fraction = max(0.03, Double(point.totalGlucides) / Double(maximum))
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

// MARK: - Aperçus

#if DEBUG
#Preview("Glucides en hausse") {
    CarteGlucidesSemaine(synthese: .mockCroissance, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Sombre") {
    CarteGlucidesSemaine(synthese: .mockCroissance, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}

#Preview("Stable") {
    CarteGlucidesSemaine(
        synthese: SyntheseGlucidesHebdo(
            moyenneCetteSemaine: 180, moyenneSemaineDerniere: 180,
            serieJournaliere: SyntheseGlucidesHebdo.mockCroissance.serieJournaliere
        ),
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Texte agrandi") {
    CarteGlucidesSemaine(synthese: .mockCroissance, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
