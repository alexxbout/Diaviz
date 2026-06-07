//
//  TableauEndormissement.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import SwiftUI

/// Contenu de la section « Endormissement » (B2, V1).
///
/// **Orienté événements, pas exhaustif.** Par défaut on ne montre que les
/// **hypos** (rares → borné, jamais de scroll infini) ; les nuits stables sont
/// résumées en un compteur (le dénominateur, pour la confiance). « Voir tout »
/// déplie la liste complète triée par glycémie de coucher croissante.
///
/// Chaque ligne = badges : glycémie de coucher · contexte (sport / IOB /
/// charge d'activité de la semaine) · issue en zones 1-2. Des faits, pas un
/// verdict ; aucune interaction au tap sur la ligne en V1 (le badge charge a
/// son propre popover).
struct TableauEndormissement: View {

    let analyse: AnalyseEndormissement

    @State private var toutAfficher = false

    private var hypos: [NuitEndormissement] {
        analyse.nuits.filter { $0.issue.estHypo }
    }

    private var nbStables: Int {
        analyse.nuits.count - hypos.count
    }

    private var lignesAffichees: [NuitEndormissement] {
        toutAfficher ? analyse.nuits : hypos
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            carteContexte

            VStack(spacing: 0) {
                ForEach(Array(lignesAffichees.enumerated()), id: \.element.id) { index, nuit in
                    if index > 0 {
                        Divider().padding(.leading, 16)
                    }
                    ligne(nuit)
                }

                if !lignesAffichees.isEmpty {
                    Divider().padding(.leading, 16)
                }
                bascule
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

            LegendeCoucher()
                .padding(.top, 2)
        }
    }

    // MARK: - Carte contexte (dose actuelle + fenêtre)

    private var carteContexte: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "syringe.fill")
                Text("\(analyse.doseActuelle.formatted()) u").bold()
            }
            .font(.title3)
            .foregroundStyle(.indigo)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.indigo.opacity(0.15))
            .clipShape(Capsule(style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Dose de lente actuelle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(analyse.nuits.count) nuits couché sous \(analyse.seuilCoucher) mg/dL depuis ce changement de dose")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Ligne (badges)

    private func ligne(_ nuit: NuitEndormissement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Ligne 1 — résultat : glycémie+tendance → issue
            HStack(spacing: 8) {
                titreGlycemie(nuit.glycemieCoucher, tendance: nuit.tendance)
                Spacer(minLength: 8)
                badgeIssue(nuit.issue)
            }
            // Ligne 2 — contexte (sous-titre nu)
            HStack(spacing: 12) {
                BadgeChargeActivite(charge: nuit.charge, avecLibelle: true)
                if let s = nuit.sport {
                    BadgeSport(seance: s)
                }
                if let iob = nuit.iob {
                    tag(systeme: "drop.fill", texte: String(format: "%.1fU", iob))
                }
                if let g = nuit.glucides {
                    tag(systeme: "fork.knife", texte: "\(g.formatted())g")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible(nuit))
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

    // MARK: Item de contexte nu (icône + valeur, sous-titre)

    private func tag(systeme: String, texte: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systeme)
            if let texte {
                Text(texte).monospacedDigit()
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    // MARK: Badge issue (zone 1-2)

    @ViewBuilder
    private func badgeIssue(_ issue: IssueEndormissement) -> some View {
        switch issue {
        case let .hypo(delai):
            Text("hypo \(delaiRelatif(delai))")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.15))
                .clipShape(Capsule(style: .continuous))

        case .stable:
            Text("stable")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule(style: .continuous))
        }
    }

    // MARK: - Ligne de bascule (dénominateur stables / Voir tout)

    private var bascule: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { toutAfficher.toggle() }
        } label: {
            HStack {
                Text(toutAfficher
                     ? "Réduire"
                     : "\(nbStables) nuits stables sous \(analyse.seuilCoucher)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: toutAfficher ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Format temps relatif depuis la lente

    /// `42` → « t+42 min », `80` → « t+1 h 20 », `120` → « t+2 h ».
    private func delaiRelatif(_ minutes: Int) -> String {
        if minutes < 60 { return "t+\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "t+\(h) h" : "t+\(h) h \(m)"
    }

    // MARK: - Accessibilité

    private func libelleAccessible(_ nuit: NuitEndormissement) -> String {
        var parts = ["Coucher à \(nuit.glycemieCoucher) \(nuit.tendance.libelle)"]
        if let s = nuit.sport { parts.append("sport \(s.resume)") }
        if let iob = nuit.iob { parts.append(String(format: "%.1f unités d'insuline active", iob)) }
        if let g = nuit.glucides { parts.append("\(g.formatted()) grammes de glucides") }
        parts.append(nuit.charge.libelle)
        switch nuit.issue {
        case let .hypo(delai): parts.append("hypo \(delaiRelatif(delai)) après la lente")
        case .stable:          parts.append("stable")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Aperçus

#Preview("Hypos + dénominateur") {
    ScrollView {
        TableauEndormissement(analyse: .mock)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))
    }
}

#Preview("Aucune hypo") {
    ScrollView {
        TableauEndormissement(analyse: .mockSansHypo)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))
    }
}
