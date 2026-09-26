//
//  CarteChargeActivite.swift
//  diaviz
//

import SwiftUI

/// Carte accueil « Activité » — **faits bruts** des 7 derniers jours :
/// séances enregistrées et marche soutenue, en minutes. Aucun niveau, aucun
/// écart à la normale : l'accueil affiche, l'interprétation (charge active
/// basse/normale/haute) vit uniquement dans Analyses → Charge et glycémie.
///
/// Mêmes faits que la charge active (`ContexteChargeActive.jours`) : séances
/// **et** marche soutenue hors séance — les deux écrans comptent la même
/// activité.
///
/// Fond plat, pas de verre — rien ne défile derrière cette carte.
struct CarteChargeActivite: View {

    let jours: [JourChargeActive]
    let marcheIncluse: Bool
    let onTap: () -> Void

    static let teinteSeances = Color.orange
    static let teinteMarche = Color.teal

    private var semaine: [JourChargeActive] { Array(jours.suffix(7)) }

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activité, 7 derniers jours. \(ligneSeances). \(ligneMarche)")
        .accessibilityHint("Ouvre le détail de l'activité sur 14 jours")
    }

    private var ligneTitre: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinteSeances)
            Text("Activité")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.teinteSeances)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    private var ligneContenu: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ligneSeances)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(ligneMarche)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            SparklineActivite(jours: semaine)
                .accessibilityHidden(true)
        }
    }

    private var ligneSeances: String {
        let nombre = semaine.reduce(0) { $0 + $1.nombreSeances }
        guard nombre > 0 else { return "Aucune séance" }
        let minutes = semaine.reduce(0) { $0 + $1.minutesSeances }
        return "\(nombre) séance\(nombre > 1 ? "s" : "") · \(DureeActivite.texte(minutes))"
    }

    private var ligneMarche: String {
        guard marcheIncluse else { return "Marche non lue depuis Apple Santé · 7 derniers jours" }
        let minutes = semaine.reduce(0) { $0 + $1.minutesMarche }
        return minutes > 0
            ? "Marche soutenue \(DureeActivite.texte(minutes)) · 7 derniers jours"
            : "Pas de marche soutenue · 7 derniers jours"
    }
}

/// « 45 min », « 2 h 10 » — durées d'activité lisibles.
enum DureeActivite {
    static func texte(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total >= 60 else { return "\(total) min" }
        let reste = total % 60
        return reste == 0 ? "\(total / 60) h" : "\(total / 60) h \(String(format: "%02d", reste))"
    }
}

// MARK: - Sparkline

/// Mini histogramme 7 barres empilées (séances + marche), hauteur
/// proportionnelle au maximum de la série, aujourd'hui en teinte pleine.
private struct SparklineActivite: View {
    let jours: [JourChargeActive]

    private static let largeurBarre: CGFloat = 5
    private static let spacing: CGFloat = 4

    private var maximum: Double {
        max(jours.map { $0.minutesSeances + $0.minutesMarche }.max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            ForEach(Array(jours.enumerated()), id: \.offset) { index, jour in
                let opacite = index == jours.count - 1 ? 1.0 : 0.5
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(CarteChargeActivite.teinteMarche.opacity(opacite))
                            .frame(height: geo.size.height * jour.minutesMarche / maximum)
                        Rectangle()
                            .fill(CarteChargeActivite.teinteSeances.opacity(opacite))
                            .frame(height: max(geo.size.height * 0.03, geo.size.height * jour.minutesSeances / maximum))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
                .frame(width: Self.largeurBarre)
            }
        }
        .frame(width: 64, height: 44)
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Activité") {
    CarteChargeActivite(jours: ContexteChargeActive.mock.jours, marcheIncluse: true, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Marche non lue") {
    CarteChargeActivite(jours: ContexteChargeActive.mock.jours, marcheIncluse: false, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
#endif
