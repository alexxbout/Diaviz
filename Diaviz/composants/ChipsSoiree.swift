//
//  ChipsSoiree.swift
//  diaviz
//

import SwiftUI

// MARK: - Taille des chips

/// Deux tailles pour la **même grammaire** de chip (SF Symbols colorés,
/// indigo pour la correction) : `compacte` dans les listes denses
/// (`LigneSoirCoucher`), `large` dans la sheet détail où la section a plus
/// d'air et mérite plus de présence visuelle.
enum TailleChip {
    case compacte
    case large

    var police: CGFloat {
        switch self { case .compacte: return 11.5; case .large: return 13 }
    }
    var padHorizontal: CGFloat {
        switch self { case .compacte: return 9; case .large: return 12 }
    }
    var padVertical: CGFloat {
        switch self { case .compacte: return 4; case .large: return 7 }
    }
    /// Même radius aux deux tailles : un chip large n'est pas une carte, il
    /// n'a pas à s'arrondir davantage — seuls la police et les paddings
    /// changent.
    var radius: CGFloat { Radius.small }
}

// MARK: - Chip de contexte

/// Petite pastille de contexte — SF Symbol + texte. La teinte **accent**
/// (indigo) marque la correction, seule à porter une couleur (frontière
/// B2/B3). Partagée entre `LigneSoirCoucher` et la sheet détail de soirée.
struct ChipContexte: View {

    struct Modele: Identifiable {
        let id = UUID()
        let symbole: String
        let texte: String
        let accent: Bool
    }

    let chip: Modele
    var taille: TailleChip = .compacte

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: chip.symbole)
            Text(chip.texte).monospacedDigit()
        }
        .font(.system(size: taille.police, weight: chip.accent ? .medium : .regular))
        .foregroundStyle(chip.accent ? Color.indigo : Color.secondary)
        .padding(.horizontal, taille.padHorizontal)
        .padding(.vertical, taille.padVertical)
        .background(
            chip.accent ? Color.indigo.opacity(0.14) : Color(.tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: taille.radius, style: .continuous)
        )
    }
}

// MARK: - Chip charge d'activité

/// Pastille dédiée à la charge — mêmes proportions que `ChipContexte`, mais
/// avec une flamme **colorée par intensité** en tête (bleu calme → orange
/// modérée → rouge intense). Couleur partagée avec `BadgeChargeActivite`
/// (`ChargeActivite.couleur`, source unique).
struct ChipCharge: View {

    let charge: ChargeActivite
    var taille: TailleChip = .compacte

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .foregroundStyle(charge.couleur)
            Text(charge.libelleCourt)
        }
        .font(.system(size: taille.police))
        .foregroundStyle(.secondary)
        .padding(.horizontal, taille.padHorizontal)
        .padding(.vertical, taille.padVertical)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: taille.radius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activité de la semaine : \(charge.libelle)")
    }
}

// MARK: - Chips d'un soir (construction partagée)

extension SoirCoucher {

    /// Chips de contexte du soir — construction **unique** partagée entre
    /// `LigneSoirCoucher` et la sheet détail (mêmes symboles, même ordre).
    var chipsContexte: [ChipContexte.Modele] {
        var chips: [ChipContexte.Modele] = []
        if let dose = correction {
            chips.append(.init(symbole: "syringe.fill", texte: "correction +\(dose.formatted())u", accent: true))
        }
        if let iob {
            chips.append(.init(symbole: "drop.fill", texte: "IOB \(String(format: "%.1f", iob))U", accent: false))
        }
        if let sport {
            chips.append(.init(symbole: "figure.run", texte: "\(sport.type) · \(sport.dureeTexte)", accent: false))
        }
        if let g = glucides {
            chips.append(.init(symbole: "fork.knife", texte: "\(g.formatted())g", accent: false))
        }
        return chips
    }

    /// Charge affichée seulement quand elle « pèse » (modérée / intense) —
    /// aucune / calme = contexte neutre, masqué pour ne pas noyer.
    var chargeVisible: Bool {
        charge == .moderee || charge == .intense
    }
}

// MARK: - Aperçu

#Preview("Chips soirée") {
    FlowLayout(spacing: 6) {
        ChipCharge(charge: .intense)
        ChipContexte(chip: .init(symbole: "syringe.fill", texte: "correction +4u", accent: true))
        ChipContexte(chip: .init(symbole: "drop.fill", texte: "IOB 1.5U", accent: false))
        ChipContexte(chip: .init(symbole: "figure.run", texte: "Course · 45 min", accent: false))
        ChipContexte(chip: .init(symbole: "fork.knife", texte: "15g", accent: false))
    }
    .padding()
}
