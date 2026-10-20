//
//  CarteVerdictBasale.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Carte « Verdict » de la tendance basale : une phrase de verdict, une
/// phrase qui dit sur quoi il repose, puis la frise des nuits qui le
/// composent. Toucher une nuit fait raconter cette nuit aux deux phrases ;
/// la toucher à nouveau revient au verdict. Textes : `ConstatVerdictBasale`.
struct CarteVerdictBasale: View {

    let constat: ConstatVerdictBasale

    @State private var selection: Int?
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    init(analyse: AnalyseBasaleDetail) {
        self.constat = ConstatVerdictBasale(analyse: analyse)
    }

    private var choisie: ConstatVerdictBasale.Pastille? {
        constat.pastilles.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(choisie?.titre ?? constat.verdict)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(choisie?.detail ?? constat.raison)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if !constat.pastilles.isEmpty {
                frise
                Text(selection == nil
                     ? "Touchez une nuit pour son détail."
                     : "Touchez-la à nouveau pour revenir au verdict.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(NiveauCarte.carte.forme)
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// Pastilles groupées au centre, écart fixe quel que soit leur nombre ;
    /// un tout petit point gris quand deux nuits retenues ne se suivent pas.
    private var frise: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(constat.pastilles) { pastille in
                if pastille.sautAvant {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 4, height: 4)
                        .padding(.top, 18)
                        .accessibilityHidden(true)
                }
                PastilleNuitVerdict(pastille: pastille, choisie: selection == pastille.id) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = reduireAnimations
                    withTransaction(transaction) {
                        selection = selection == pastille.id ? nil : pastille.id
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pastille d'une nuit

private struct PastilleNuitVerdict: View {

    let pastille: ConstatVerdictBasale.Pastille
    let choisie: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                rond
                    .overlay {
                        if choisie {
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: 2)
                                .padding(-5)
                        }
                    }
                Text(jour)
                    .font(.subheadline)
                    .fontWeight(choisie ? .semibold : .regular)
                    .foregroundStyle(choisie ? .primary : .secondary)
                    .monospacedDigit()
            }
            .frame(width: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pastille.titre)
        .accessibilityHint(pastille.detail)
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }

    @ViewBuilder
    private var rond: some View {
        switch pastille.etat {
        case .aVenir:
            Circle()
                .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                .frame(width: 32, height: 32)
        default:
            Circle()
                .fill(couleur)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icone)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
        }
    }

    private var couleur: Color {
        switch pastille.etat {
        case .concluante:                         return .green
        case .deriveMontante, .deriveDescendante: return .orange
        case .hypo:                               return .red
        case .aVenir:                             return .clear
        }
    }

    private var icone: String {
        switch pastille.etat {
        case .concluante:                    return "checkmark"
        case .deriveMontante:                return "arrow.up.right"
        case .deriveDescendante, .hypo:      return "arrow.down.right"
        case .aVenir:                        return ""
        }
    }

    /// Numéro du jour, vide pour une place à venir (garde la hauteur).
    private var jour: String {
        guard let date = pastille.date else { return " " }
        return "\(Calendar.current.component(.day, from: date))"
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Verdict - pipeline synthétique") {
    CarteVerdictBasale(analyse: CalculAnalyseBasale.apercu())
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Verdict - Recent change") {
    CarteVerdictBasale(analyse: .mockRecentChange)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Verdict - No data") {
    CarteVerdictBasale(analyse: .mockNoData)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
#endif
