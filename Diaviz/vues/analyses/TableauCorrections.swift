//
//  TableauCorrections.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import SwiftUI

/// Contenu de la section « Corrections du soir » (B3, V1 rétrospective).
///
/// Tableau des corrections passées prises au coucher, trié par glycémie de
/// correction croissante. Chaque ligne = badges : glycémie · dose de
/// correction · contexte (charge / sport / IOB) · issue classée en 3 états
/// (insuffisant / adapté / sur-correction).
///
/// **Garde-fou régulatoire** : on montre ce qui s'est passé (fait), jamais
/// une dose à prendre. Aucune recommandation.
struct TableauCorrections: View {

    let analyse: AnalyseCorrections

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(analyse.nombre) corrections au coucher")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(analyse.corrections.enumerated()), id: \.element.id) { index, c in
                    if index > 0 {
                        Divider().padding(.leading, 16)
                    }
                    ligne(c)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

            Text("Rétrospectif — ce qui s'est passé, pas une dose à prendre.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            LegendeCoucher()
                .padding(.top, 2)
        }
    }

    // MARK: - Ligne (badges)

    private func ligne(_ c: CorrectionSoir) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Ligne 1 — résultat : glycémie+tendance → issue
            HStack(spacing: 8) {
                titreGlycemie(c.glycemie, tendance: c.tendance)
                Spacer(minLength: 8)
                badgeIssue(c.issue)
            }
            // Ligne 2 — dose corrigée + contexte (sous-titre nu)
            HStack(spacing: 12) {
                badgeDose(c.dose)
                BadgeChargeActivite(charge: c.charge, avecLibelle: true)
                if let s = c.sport {
                    BadgeSport(seance: s)
                }
                if let iob = c.iob {
                    tag(systeme: "drop.fill", texte: String(format: "%.1fU", iob))
                }
                if let g = c.glucides {
                    tag(systeme: "fork.knife", texte: "\(g.formatted())g")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible(c))
    }

    // MARK: Titre glycémie (gros chiffre + tendance, sans fond)

    private func titreGlycemie(_ valeur: Int, tendance: TendanceGlycemie) -> some View {
        HStack(spacing: 5) {
            Text("\(valeur)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Image(systemName: tendance.symbole)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Dose de correction (nu, teal)

    private func badgeDose(_ dose: Double) -> some View {
        Text("+\(dose.formatted()) u")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.teal)
    }

    // MARK: Item de contexte nu (icône + valeur, sous-titre)

    private func tag(systeme: String, texte: String? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systeme)
            if let texte {
                Text(texte).monospacedDigit()
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    // MARK: Badge issue (3 états : icône + texte)

    @ViewBuilder
    private func badgeIssue(_ issue: IssueCorrection) -> some View {
        switch issue {
        case .insuffisant:
            badgeIssueContenu(systeme: "arrow.up", texte: "insuffisant", couleur: .orange)
        case .adapte:
            badgeIssueContenu(systeme: "checkmark", texte: "adapté", couleur: .green)
        case .surCorrection:
            badgeIssueContenu(systeme: "arrow.down", texte: "sur-correction", couleur: .red)
        }
    }

    private func badgeIssueContenu(systeme: String, texte: String, couleur: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systeme)
            Text(texte)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(couleur)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(couleur.opacity(0.15))
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Accessibilité

    private func libelleAccessible(_ c: CorrectionSoir) -> String {
        var parts = ["Glycémie \(c.glycemie) \(c.tendance.libelle)", "correction \(c.dose.formatted()) unités"]
        if let s = c.sport { parts.append("sport \(s.resume)") }
        if let iob = c.iob { parts.append(String(format: "%.1f unités d'insuline active", iob)) }
        if let g = c.glucides { parts.append("\(g.formatted()) grammes de glucides") }
        parts.append(c.charge.libelle)
        switch c.issue {
        case .insuffisant:   parts.append("résultat insuffisant")
        case .adapte:        parts.append("résultat adapté")
        case .surCorrection: parts.append("sur-correction")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Aperçu

#Preview("Tableau corrections") {
    ScrollView {
        TableauCorrections(analyse: .mock)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))
    }
}
