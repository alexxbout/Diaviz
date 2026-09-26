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
    private var afficheContexte: Bool { !soir.chipsContexte().isEmpty || soir.chargeVisible }

    private var carte: some View {
        VStack(alignment: .leading, spacing: afficheContexte ? 9 : 0) {
            enTete
            if afficheContexte {
                FlowLayout(spacing: 6) {
                    if soir.chargeVisible, let charge = soir.charge {
                        ChipCharge(charge: charge)
                    }
                    ForEach(soir.chipsContexte()) { chip in
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
        .clipShape(NiveauCarte.carte.forme)
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
        // Ni hypo ni soir calme : un resucrage préventif a été pris et la
        // glycémie n'est jamais descendue. Distinguer les deux est tout
        // l'intérêt — c'est le soir le plus instructif de la liste.
        if soir.hypoEvitee {
            return Issue(constat: "hypo évitée", precision: "resucrage préventif", couleur: .orange)
        }
        return Issue(constat: "stable", precision: nil, couleur: .green)
    }

    // MARK: - Accessibilité

    private var libelleAccessible: String {
        var parts = ["\(soir.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))",
                     "couché à \(soir.glycemie) mg/dL",
                     issue.constat]
        if let p = issue.precision { parts.append(p) }
        if soir.chargeVisible, let charge = soir.charge { parts.append(charge.libelle.lowercased()) }
        parts += soir.chipsContexte().map { "\($0.texte)" }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Flow layout (wrap horizontal)

/// Layout **flow** minimal : dispose les enfants de gauche à droite, passe à la
/// ligne quand la largeur est dépassée. Utilisé pour la rangée de chips.
///
/// `sizeThatFits` et `placeSubviews` partagent volontairement le même calcul
/// de rangées (`rangees(largeurMax:subviews:)`). Quand les deux divergeaient,
/// la hauteur annoncée valait celle d'**une seule** rangée (mesure faite sur
/// une largeur non spécifiée, donc infinie) alors que le placement en repliait
/// plusieurs : la carte parente clippait les chips en trop, et une rangée de
/// badges un peu longue devenait invisible.
struct FlowLayout: Layout {

    var spacing: CGFloat = 6

    /// Découpe les enfants en rangées pour une largeur donnée, et rend la
    /// taille de chacun — seule source de vérité du layout.
    private func rangees(
        largeurMax: CGFloat,
        subviews: Subviews
    ) -> [[(indice: Int, taille: CGSize)]] {
        var rangees: [[(indice: Int, taille: CGSize)]] = [[]]
        var largeurRangee: CGFloat = 0

        for (indice, subview) in subviews.enumerated() {
            let taille = subview.sizeThatFits(.unspecified)
            let largeurAjoutee = rangees[rangees.count - 1].isEmpty
                ? taille.width
                : taille.width + spacing

            if largeurRangee + largeurAjoutee > largeurMax, !rangees[rangees.count - 1].isEmpty {
                rangees.append([])
                largeurRangee = taille.width
            } else {
                largeurRangee += largeurAjoutee
            }
            rangees[rangees.count - 1].append((indice, taille))
        }
        return rangees
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        // `replacingUnspecifiedDimensions` plutôt qu'un fallback `.infinity` :
        // une largeur infinie mettrait tout sur une rangée et sous-estimerait
        // la hauteur.
        let tailleParDefaut = CGSize(width: CGFloat.infinity, height: CGFloat(0))
        let largeurMax: CGFloat = proposal
            .replacingUnspecifiedDimensions(by: tailleParDefaut)
            .width
        let rangees = rangees(largeurMax: largeurMax, subviews: subviews)

        var largeur: CGFloat = 0
        var hauteur: CGFloat = 0

        for (index, rangee) in rangees.enumerated() {
            var largeurRangee: CGFloat = 0
            var hauteurRangee: CGFloat = 0
            for element in rangee {
                largeurRangee += element.taille.width
                hauteurRangee = max(hauteurRangee, element.taille.height)
            }
            largeurRangee += CGFloat(rangee.count - 1) * spacing
            largeur = max(largeur, largeurRangee)
            hauteur += hauteurRangee
            if index > 0 { hauteur += spacing }
        }

        return CGSize(width: min(largeur, largeurMax), height: hauteur)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY

        for rangee in rangees(largeurMax: bounds.width, subviews: subviews) {
            var x = bounds.minX
            var hauteurRangee: CGFloat = 0
            for element in rangee {
                subviews[element.indice].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(element.taille)
                )
                x += element.taille.width + spacing
                hauteurRangee = max(hauteurRangee, element.taille.height)
            }
            y += hauteurRangee + spacing
        }
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Lignes soir — états") {
    let base = Date()
    let soirs: [SoirCoucher] = [
        SoirCoucher(id: UUID(), date: base, dateNuit: base, glycemie: 132, tendance: .baisse,
                    correction: nil, glucides: 15,
                    sport: SportResume(type: "Course", intensite: "modéré", dureeMinutes: 45),
                    iob: nil, charge: .haute, categorieB1: .tendanceBasse,
                    enHypo: true, delaiHypoMinutes: 42, issueCorrection: nil),
        SoirCoucher(id: UUID(), date: base, dateNuit: base, glycemie: 205, tendance: .hausse,
                    correction: 4, glucides: nil, sport: nil, iob: 1.5,
                    charge: .haute, categorieB1: nil,
                    enHypo: true, delaiHypoMinutes: nil, issueCorrection: .surCorrection),
        SoirCoucher(id: UUID(), date: base, dateNuit: base, glycemie: 240, tendance: .hausse,
                    correction: 3, glucides: nil, sport: nil, iob: nil,
                    charge: .normale, categorieB1: nil,
                    enHypo: false, delaiHypoMinutes: nil, issueCorrection: .insuffisant),
        SoirCoucher(id: UUID(), date: base, dateNuit: base, glycemie: 109, tendance: .stable,
                    correction: nil, glucides: 15, sport: nil, iob: nil,
                    charge: nil, categorieB1: .stable,
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
