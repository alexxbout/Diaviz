//
//  LigneSoirCoucher.swift
//  diaviz
//

import SwiftUI

/// Ligne d'un **soir analysé** (fusion B2 + B3) — composant **réutilisable**
/// entre la page « Hypos au coucher » et la sheet « Comparer à ce soir ».
///
/// Structure (validée en chat) :
/// - **liseré** gauche coloré par l'issue (rouge hypo/sur-correction, orange
///   « resté haut », vert stable) — constat scannable d'un coup d'œil ;
/// - **glycémie en héros** (+ flèche de tendance) et date en dessous ;
/// - **issue en toutes lettres** à droite, sur deux lignes (constat + précision
///   factuelle) ;
/// - **chips de contexte** sur leur propre ligne (correction en teinte teal =
///   frontière B2/B3 visible ; IOB, sport, charge, glucides). Rangée masquée
///   si aucun contexte.
///
/// Purement factuel : décrit ce qui s'est passé, jamais un conseil.
struct LigneSoirCoucher: View {

    let soir: SoirCoucher
    /// Optionnel — ouvre le détail de la soirée (sheet à venir). Sans closure,
    /// la ligne est un simple bloc non tappable (usage dans la sheet comparer).
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) { carte }
                .buttonStyle(.plain)
        } else {
            carte
        }
    }

    /// La barre de couleur vit en **overlay** (pas en sibling `HStack`) :
    /// un `Rectangle` à côté d'un `VStack` dans un `HStack` force une
    /// négociation de largeur qui fait parfois calculer la hauteur de la
    /// carte **avant** que `FlowLayout` ait fini de replier ses chips sur
    /// plusieurs lignes — la carte se fige trop courte et coupe la dernière
    /// ligne. En overlay, la hauteur suit uniquement le `VStack` de contenu.
    private var afficheContexte: Bool { !contexte.isEmpty || afficherCharge }

    private var carte: some View {
        VStack(alignment: .leading, spacing: afficheContexte ? 9 : 0) {
            enTete
            if afficheContexte {
                FlowLayout(spacing: 6) {
                    if afficherCharge {
                        ChipCharge(charge: soir.charge)
                    }
                    ForEach(contexte) { chip in
                        ChipContexte(chip: chip)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(issue.couleur)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible)
    }

    // MARK: - En-tête (glycémie héros + issue)

    private var enTete: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(soir.glycemie)")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Image(systemName: soir.tendance.symbole)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(soir.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(issue.constat)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(issue.couleur)
                if let precision = issue.precision {
                    Text(precision)
                        .font(.caption2)
                        .foregroundStyle(issue.couleur.opacity(0.85))
                }
            }
            .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Issue (constat + couleur + précision)

    private struct Issue {
        let constat: String
        let precision: String?
        let couleur: Color
    }

    private var issue: Issue {
        if soir.enHypo {
            if let delai = soir.delaiHypoMinutes {
                return Issue(constat: "hypo", precision: "t+\(delai) min après la lente", couleur: .red)
            }
            if soir.issueCorrection == .surCorrection {
                return Issue(constat: "sur-correction", precision: "hypo dans les 6 h", couleur: .red)
            }
            return Issue(constat: "hypo", precision: nil, couleur: .red)
        }
        if soir.issueCorrection == .insuffisant {
            return Issue(constat: "resté haut", precision: "au-dessus de la cible", couleur: .orange)
        }
        return Issue(constat: "stable", precision: nil, couleur: .green)
    }

    // MARK: - Chips de contexte

    private var contexte: [ChipContexte.Modele] {
        var chips: [ChipContexte.Modele] = []
        if let dose = soir.correction {
            chips.append(.init(symbole: "syringe.fill", texte: "correction +\(dose.formatted())u", accent: true))
        }
        if let iob = soir.iob {
            chips.append(.init(symbole: "drop.fill", texte: "IOB \(String(format: "%.1f", iob))U", accent: false))
        }
        if let sport = soir.sport {
            chips.append(.init(symbole: "figure.run", texte: "\(sport.type) · \(sport.dureeTexte)", accent: false))
        }
        if let g = soir.glucides {
            chips.append(.init(symbole: "fork.knife", texte: "\(g.formatted())g", accent: false))
        }
        return chips
    }

    /// Charge affichée seulement quand elle « pèse » (modérée / intense) —
    /// aucune / calme = contexte neutre, masqué pour ne pas noyer la ligne.
    private var afficherCharge: Bool {
        soir.charge == .moderee || soir.charge == .intense
    }

    private var libelleAccessible: String {
        var parts = ["\(soir.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))",
                     "couché à \(soir.glycemie) mg/dL",
                     issue.constat]
        if let p = issue.precision { parts.append(p) }
        if afficherCharge { parts.append("activité de la semaine : \(soir.charge.libelle.lowercased())") }
        parts += contexte.map { "\($0.texte)" }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Flow layout (wrap horizontal)

/// Layout **flow** minimal : dispose les enfants de gauche à droite, passe à la
/// ligne quand la largeur est dépassée. Utilisé pour la rangée de chips.
struct FlowLayout: Layout {

    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, largeur: CGFloat = 0
        for subview in subviews {
            let taille = subview.sizeThatFits(.unspecified)
            if x + taille.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += taille.width + spacing
            rowHeight = max(rowHeight, taille.height)
            largeur = max(largeur, x - spacing)
        }
        return CGSize(width: largeur, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let taille = subview.sizeThatFits(.unspecified)
            if x + taille.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(taille))
            x += taille.width + spacing
            rowHeight = max(rowHeight, taille.height)
        }
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Lignes soir — états") {
    let base = Date()
    let soirs: [SoirCoucher] = [
        SoirCoucher(id: UUID(), date: base, glycemie: 132, tendance: .baisse,
                    correction: nil, glucides: 15,
                    sport: SportResume(type: "Course", intensite: "modéré", dureeMinutes: 45),
                    iob: nil, charge: .intense, categorieB1: .tendanceBasse,
                    enHypo: true, delaiHypoMinutes: 42, issueCorrection: nil),
        SoirCoucher(id: UUID(), date: base, glycemie: 205, tendance: .hausse,
                    correction: 4, glucides: nil, sport: nil, iob: 1.5,
                    charge: .intense, categorieB1: nil,
                    enHypo: true, delaiHypoMinutes: nil, issueCorrection: .surCorrection),
        SoirCoucher(id: UUID(), date: base, glycemie: 240, tendance: .hausse,
                    correction: 3, glucides: nil, sport: nil, iob: nil,
                    charge: .calme, categorieB1: nil,
                    enHypo: false, delaiHypoMinutes: nil, issueCorrection: .insuffisant),
        SoirCoucher(id: UUID(), date: base, glycemie: 109, tendance: .stable,
                    correction: nil, glucides: 15, sport: nil, iob: nil,
                    charge: .aucune, categorieB1: .stable,
                    enHypo: false, delaiHypoMinutes: nil, issueCorrection: nil),
    ]
    return ScrollView {
        VStack(spacing: 8) {
            ForEach(soirs) { LigneSoirCoucher(soir: $0, onTap: {}) }
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
