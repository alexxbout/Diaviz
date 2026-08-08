//
//  RecapDosesRepas.swift
//  diaviz
//

import SwiftUI

/// Ventilation des doses d'un repas, dans un cadre unique posé en **row
/// sœur** de `LigneRepas` dans la même `Section` du journal.
///
/// Le contexte libre n'est pas ici mais en badge sous l'en-tête
/// (`LigneRepas.badgeContexte`) : il qualifie le repas, pas ses doses.
///
/// Une row sœur et non un bloc dans `LigneRepas` : une row tappable qui
/// grandit éloigne d'autant le chevron du `NavigationLink`, centré
/// verticalement sur toute sa hauteur, et un bloc pleine largeur juste sous
/// la mini-courbe la fait passer au second plan. En row séparée, l'en-tête
/// reste compact et la courbe garde la vedette.
///
/// Un cadre unique et non des rows individuelles : une row par dose ajoutait
/// autant de séparateurs natifs, et l'empilement devenait beaucoup trop dense
/// face aux rows d'aliments qui suivent.
///
/// N'émet rien sur un repas ordinaire — dose unique, sans ajustement ni
/// correction : la dose est alors déjà lisible dans la sous-ligne de
/// `LigneRepas`, une ventilation à une seule valeur n'apprendrait rien.
struct RecapDosesRepas: View {

    let repas: Repas

    /// La ventilation n'a de sens que si un terme s'ajoute à la dose de base.
    /// `Repas.totalInsuline` ne porte que celle-ci — ajustements et correction
    /// sont stockés à part et modifient tous deux le total réellement injecté.
    private var afficheVentilation: Bool {
        (repas.doseCorrection ?? 0) > 0 || !repas.ajustements.isEmpty
    }

    var body: some View {
        if afficheVentilation {
            ventilation
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                )
        }
    }

    // MARK: - Ventilation

    /// Tous les termes de la somme sont alignés dans la même colonne — y
    /// compris les ajustements, dont la `valeur` s'ajoute bien à la dose de
    /// base (elle n'y est pas déjà incluse, cf. `Repas.totalInjecte`). La
    /// colonne se vérifie donc de haut en bas : base ± ajustements +
    /// correction = total.
    private var ventilation: some View {
        VStack(spacing: 4) {
            ligne("Repas", valeur: repas.totalInsuline, couleur: .secondary)

            ForEach(repas.ajustements) { ajustement in
                ligne(
                    libelleAjustement(ajustement),
                    texteValeur: ajustement.valeur.ecartDoseFormate,
                    couleur: .blue
                )
            }

            if let correction = repas.doseCorrection, correction > 0 {
                ligne("Correction", texteValeur: correction.ecartDoseFormate, couleur: .orange)
            }

            Divider()

            ligne("Total injecté", valeur: repas.totalInjecte, couleur: .primary, enGras: true)
        }
    }

    /// « Sport récent · Course à pied » — le type de sport détecté qualifie la
    /// raison quand il est connu. L'écart de dose n'est pas dans le libellé :
    /// il occupe la colonne de valeurs, comme les autres termes.
    private func libelleAjustement(_ ajustement: Ajustement) -> String {
        ajustement.typeSportDetecte.map { "\(ajustement.raison.libelle) · \($0)" }
            ?? ajustement.raison.libelle
    }

    // MARK: - Rows

    private func ligne(
        _ libelle: String,
        valeur: Double,
        couleur: Color,
        enGras: Bool = false
    ) -> some View {
        ligne(libelle, texteValeur: valeur.doseInsulineFormatee, couleur: couleur, enGras: enGras)
    }

    private func ligne(
        _ libelle: String,
        texteValeur: String,
        couleur: Color,
        enGras: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Text(libelle)
                .foregroundStyle(enGras ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(texteValeur)
                .foregroundStyle(couleur)
                .fontWeight(enGras ? .semibold : .regular)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

}

// MARK: - Aperçus

private func _apercuHeure(_ h: Int, _ m: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
}

#Preview("Correction + ajustement + contexte") {
    List {
        Section("Dîner") {
            RecapDosesRepas(
                repas: Repas(
                    heure: _apercuHeure(21, 39),
                    aliments: [Aliment(emoji: "🍝", nom: "Pâtes", quantite: 180, glucides: 92, insuline: 9.5)],
                    doseCorrection: 1,
                    ajustements: [
                        Ajustement(raison: .sportRecent, valeur: -1, typeSportDetecte: "Course à pied")
                    ],
                    contexteLibre: "Je prends la voiture"
                )
            )
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Correction seule") {
    List {
        Section("Petit déjeuner") {
            RecapDosesRepas(
                repas: Repas(
                    heure: _apercuHeure(11, 32),
                    aliments: [Aliment(emoji: "🍎", nom: "Pomme", quantite: 160, glucides: 89, insuline: 9)],
                    doseCorrection: 3
                )
            )
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Repas ordinaire — n'émet rien") {
    List {
        Section("Déjeuner") {
            RecapDosesRepas(
                repas: Repas(
                    heure: _apercuHeure(12, 30),
                    aliments: [Aliment(emoji: "🍚", nom: "Riz", quantite: 150, glucides: 45, insuline: 4)]
                )
            )
        }
    }
    .listStyle(.insetGrouped)
}
