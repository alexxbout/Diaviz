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

/// Pastille dédiée à la charge active du jour — mêmes proportions que
/// `ChipContexte`, avec une flamme **colorée par niveau** en tête
/// (`NiveauChargeActive.couleur`, source unique).
struct ChipCharge: View {

    let charge: NiveauChargeActive
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
        .accessibilityLabel(charge.libelle)
    }
}

// MARK: - Chip de critère (filtre de recherche)

/// Chip **tappable** de la recherche « Comparer à ce soir » : un critère de
/// contexte qu'on active pour rétrécir le corpus.
///
/// Elle porte son **compteur** — le nombre de soirs qui resteraient si le
/// critère était ajouté aux critères déjà actifs. Avec ~60 nuits d'historique,
/// c'est ce qui rend le filtrage utilisable : on voit le coût d'un critère
/// avant de le poser. Un critère qui viderait la liste est désactivé plutôt
/// que de mener à un écran vide sans coupable identifiable.
///
/// Teinte d'accent (et non l'indigo des corrections) : ici la couleur dit
/// « sélectionné », pas « c'est une correction ».
struct ChipCritereCoucher: View {

    let critere: CritereCoucher
    let actif: Bool
    /// Soirs restants si le critère était activé. `nil` tant qu'aucune
    /// glycémie n'est saisie — il n'y a alors pas de base à compter.
    let compte: Int?
    let action: () -> Void

    /// Inutilisable : l'activer ne laisserait aucun soir.
    private var indisponible: Bool { !actif && compte == 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: critere.symbole)
                Text(critere.libelle)
                if let compte {
                    Text("· \(compte)")
                        .monospacedDigit()
                        .foregroundStyle(actif ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.6))
                }
            }
            .font(.system(size: 13, weight: actif ? .medium : .regular))
            .foregroundStyle(couleurTexte)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(fond, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay {
                if actif {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(indisponible)
        .accessibilityLabel(critere.libelle)
        .accessibilityValue(libelleAccessible)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
        .accessibilityHint(indisponible ? "Aucun soir avec ce critère" : "Restreint la recherche")
    }

    private var couleurTexte: Color {
        if indisponible { return .secondary.opacity(0.5) }
        return actif ? .accentColor : .secondary
    }

    private var fond: Color {
        actif ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill)
    }

    private var libelleAccessible: String {
        guard let compte else { return actif ? "actif" : "inactif" }
        let etat = actif ? "actif" : "inactif"
        return "\(etat), \(compte) soir\(compte > 1 ? "s" : "")"
    }
}

// MARK: - Chips d'un soir (construction partagée)

extension SoirCoucher {

    /// Chips de contexte du soir — construction **unique** partagée entre
    /// `LigneSoirCoucher` et la sheet détail (mêmes symboles, même ordre).
    ///
    /// `avecGlucides` est à `false` dans la sheet détail : la timeline y
    /// détaille déjà chaque prise (repas, resucrage) avec son heure et son
    /// intention — un total agrégé n'y apprend rien.
    func chipsContexte(avecGlucides: Bool = true) -> [ChipContexte.Modele] {
        var chips: [ChipContexte.Modele] = []
        if let dose = correction {
            chips.append(.init(symbole: "syringe.fill", texte: "correction +\(dose.formatted())u", accent: true))
        }
        if let iob {
            chips.append(.init(symbole: "drop.fill", texte: "IOB coucher \(String(format: "%.1f", iob))U", accent: false))
        }
        if let sport {
            chips.append(.init(symbole: "figure.run", texte: "\(sport.type) · \(sport.dureeTexte)", accent: false))
        }
        if avecGlucides, let g = glucides {
            chips.append(.init(symbole: "fork.knife", texte: "\(g.formatted())g", accent: false))
        }
        return chips
    }

    /// Charge affichée seulement quand elle sort de la normale — normale ou
    /// inconnue = contexte neutre, masqué pour ne pas noyer.
    var chargeVisible: Bool {
        charge == .basse || charge == .haute
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Chips soirée") {
    FlowLayout(spacing: 6) {
        ChipCharge(charge: .haute)
        ChipContexte(chip: .init(symbole: "syringe.fill", texte: "correction +4u", accent: true))
        ChipContexte(chip: .init(symbole: "drop.fill", texte: "IOB 1.5U", accent: false))
        ChipContexte(chip: .init(symbole: "figure.run", texte: "Course · 45 min", accent: false))
        ChipContexte(chip: .init(symbole: "fork.knife", texte: "15g", accent: false))
    }
    .padding()
}
#endif
