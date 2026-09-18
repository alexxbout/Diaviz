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
                // Hero = le **niveau actuel** en mot (basse/normale/haute),
                // pas l'écart brut : un pourcentage seul obligeait à faire
                // le calcul mental pour savoir où on en est.
                Text(niveau.libelle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(niveau.couleur(teinteDefaut: Self.teinte))
                // Une seule ligne secondaire : écart chiffré + tendance
                // fusionnés (au lieu de deux lignes qui répétaient « vs
                // normale »).
                Text(ligneDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            SparklineCharge(serie: Array(synthese.serieJournaliere.suffix(7)), teinte: Self.teinte)
                .accessibilityHidden(true)
        }
    }

    /// Niveau courant vs normale perso — même seuil que la détection de
    /// tendance (`CalculChargeContinue.seuilEcartTendance`), pour que le mot
    /// affiché et la tendance racontent toujours la même histoire.
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

        func couleur(teinteDefaut: Color) -> Color {
            switch self {
            case .basse:    return .red
            case .haute:    return .blue
            case .normale:  return .primary
            case .inconnue: return .primary
            }
        }
    }

    private var niveau: Niveau {
        guard let ecart = synthese.ecartRelatif else { return .inconnue }
        if ecart <= -CalculChargeContinue.seuilEcartTendance { return .basse }
        if ecart >= CalculChargeContinue.seuilEcartTendance { return .haute }
        return .normale
    }

    /// « −22 % vs normale · en baisse depuis 5 j », ou juste la tendance
    /// quand l'écart n'est pas calculable.
    private var ligneDetail: String {
        let ecartTexte = synthese.ecartRelatif.map { "\(ecartFormate($0)) vs normale" }
        switch synthese.tendance {
        case .enBaisse(let jours):
            return [ecartTexte, "en baisse depuis \(jours) j"].compactMap { $0 }.joined(separator: " · ")
        case .enHausse(let jours):
            return [ecartTexte, "en hausse depuis \(jours) j"].compactMap { $0 }.joined(separator: " · ")
        case .stable:
            return ecartTexte ?? "pas d'activité récente sur 4 semaines"
        }
    }

    /// Signe explicite (« +12 % » / « −22 % »), même convention que les
    /// deltas glucides — un écart relatif se lit toujours signé.
    private func ecartFormate(_ ecart: Double) -> String {
        let pct = Int((ecart * 100).rounded())
        let signe = pct > 0 ? "+" : (pct < 0 ? "\u{2212}" : "")
        return "\(signe)\(abs(pct))%"
    }

    private var libelleAccessibilite: String {
        "\(niveau.libelle), \(ligneDetail)"
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
