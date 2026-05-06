//
//  CarteScoreQuotidien.swift
//  insulog
//
//  Created by Alexandre on 06/05/2026.
//

import SwiftUI

/// Carte « score quotidien » — résumé glycémique de la veille.
///
/// Format paysage. De gauche à droite : emoji représentatif du segment
/// du score, libellé « HIER » + score sur 100, mini-historique en
/// barres verticales des 7 derniers jours (style Apple Health), et
/// chevron indiquant que la carte est tappable. La carte entière est
/// un bouton accessible : `onTap` ouvre la sheet de détails.
struct CarteScoreQuotidien: View {

    /// Score sur 100 affiché sous « HIER ». `nil` quand la couverture
    /// CGM est insuffisante pour un calcul fiable — la carte affiche
    /// alors l'emoji 🤷 et « Données insuffisantes ».
    let score: Int?

    /// Date du score affiché. Utilisée comme graine pour rendre la
    /// sélection d'emoji stable (même date + même score = même emoji),
    /// pour qu'il ne « clignote » pas entre re-renders et qu'il
    /// change naturellement à minuit.
    let date: Date

    /// 7 derniers scores, du plus ancien au plus récent. Le dernier
    /// élément correspond à `date`. Les valeurs `nil` sont rendues en
    /// barres « fantômes » (contour seul, opacité 0.2).
    let historique: [Int?]

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 44))
                    .accessibilityHidden(true)

                blocTexte

                Spacer(minLength: 12)

                BarresHistorique(historique: historique, scoreActuel: score)
                    .accessibilityHidden(true)

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color(.separator).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelleAccessibilite)
        .accessibilityHint("Ouvre les détails du score")
    }

    /// Bloc texte « HIER + score ». Extrait du `body` pour éviter un
    /// time-out de type-check du compilateur sur l'imbrication HStack
    /// dans VStack dans HStack avec interpolation et chaînes de modifiers.
    @ViewBuilder
    private var blocTexte: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HIER")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let score {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(score))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("/ 100")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Données insuffisantes")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emoji: String {
        guard let score else { return "🤷" }
        return Self.emojiDuJour(score: score, date: date)
    }

    private var libelleAccessibilite: String {
        if let score {
            return "Score d'hier : \(score) sur 100"
        }
        return "Score d'hier indisponible"
    }
}

// MARK: - Segments de score

/// Segments métier du score (0–100). Mêmes bornes pour la sélection
/// d'emoji et — via `CouleurScore.couleur(pour:)` plus bas — pour la
/// couleur d'accent.
private enum SegmentScore {
    case excellent  // 90–100
    case bon        // 75–89
    case correct    // 60–74
    case moyen      // 45–59
    case faible     // 30–44
    case mauvais    // 0–29

    init(score: Int) {
        switch score {
        case 90...:    self = .excellent
        case 75...89:  self = .bon
        case 60...74:  self = .correct
        case 45...59:  self = .moyen
        case 30...44:  self = .faible
        default:       self = .mauvais
        }
    }

    var emojis: [String] {
        switch self {
        case .excellent: return ["🤩", "🥳", "😄"]
        case .bon:       return ["😎", "😊", "🙂"]
        case .correct:   return ["🙂", "😌", "😏"]
        case .moyen:     return ["😐", "😶", "🤔"]
        case .faible:    return ["😟", "😕", "😬"]
        case .mauvais:   return ["😩", "😣", "😖"]
        }
    }
}

// MARK: - Couleur d'accent du score

private enum CouleurScore {
    /// Trois paliers seulement (≥70 / 50–69 / <50) — volontairement
    /// plus grossiers que les six segments d'emoji pour rester
    /// lisibles en un coup d'œil.
    static func couleur(pour score: Int) -> Color {
        switch score {
        case 70...:   return Color(red: 0.114, green: 0.620, blue: 0.459)
        case 50..<70: return .orange
        default:      return .red
        }
    }
}

// MARK: - Sélection d'emoji déterministe

extension CarteScoreQuotidien {
    /// Sélectionne un emoji du segment de `score`, de manière
    /// déterministe à partir du jour calendaire de `date`. La même
    /// (date, score) renvoie toujours le même emoji.
    static func emojiDuJour(score: Int, date: Date) -> String {
        let candidats = SegmentScore(score: score).emojis
        let graine = abs(cleJour(pour: date) &+ score &* 31)
        return candidats[graine % candidats.count]
    }

    private static func cleJour(pour date: Date) -> Int {
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: date
        )
        let a = comps.year ?? 0
        let m = comps.month ?? 0
        let j = comps.day ?? 0
        return a * 10_000 + m * 100 + j
    }
}

// MARK: - Mini-graphique 7 jours

private struct BarresHistorique: View {
    let historique: [Int?]
    /// Score affiché par la carte — utilisé uniquement pour colorer la
    /// dernière barre. Si `nil`, la dernière barre reste neutre.
    let scoreActuel: Int?

    private let largeurBarre: CGFloat = 5
    private let espaceBarres: CGFloat = 3
    private let hauteurTotale: CGFloat = 44
    private let rayonCoin: CGFloat = 1.5
    /// Plancher visuel : un score très bas (1–2) doit rester perceptible.
    private let hauteurMin: CGFloat = 2

    var body: some View {
        HStack(alignment: .bottom, spacing: espaceBarres) {
            ForEach(Array(historique.enumerated()), id: \.offset) { index, valeur in
                barre(pour: valeur, estActuelle: index == historique.count - 1)
            }
        }
        .frame(height: hauteurTotale, alignment: .bottom)
    }

    @ViewBuilder
    private func barre(pour valeur: Int?, estActuelle: Bool) -> some View {
        if let valeur {
            let borne = max(0, min(100, valeur))
            let hauteur = max(hauteurMin, hauteurTotale * CGFloat(borne) / 100)
            RoundedRectangle(cornerRadius: rayonCoin, style: .continuous)
                .fill(couleurBarre(estActuelle: estActuelle))
                .frame(width: largeurBarre, height: hauteur)
        } else {
            RoundedRectangle(cornerRadius: rayonCoin, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                .frame(width: largeurBarre, height: hauteurTotale)
        }
    }

    private func couleurBarre(estActuelle: Bool) -> Color {
        guard estActuelle, let scoreActuel else {
            return Color.secondary.opacity(0.5)
        }
        return CouleurScore.couleur(pour: scoreActuel)
    }
}

// MARK: - Aperçus

#Preview("Score 82 — historique varié") {
    CarteScoreQuotidien(
        score: 82,
        date: Date(),
        historique: [65, 78, 71, 55, 88, 73, 82],
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Score 35 — historique bas") {
    CarteScoreQuotidien(
        score: 35,
        date: Date(),
        historique: [42, 38, 28, 45, 33, 40, 35],
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Score indisponible") {
    CarteScoreQuotidien(
        score: nil,
        date: Date(),
        historique: [60, nil, 72, 58, nil, 65, nil],
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Score 95 — sombre") {
    CarteScoreQuotidien(
        score: 95,
        date: Date(),
        historique: [88, 92, 85, 90, 94, 89, 95],
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
