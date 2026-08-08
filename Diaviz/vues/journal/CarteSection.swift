//
//  CarteSection.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Carte de section compacte, style **Liquid Glass teinté** (iOS 26) :
///
/// - **Fond** : `.glassEffect(.regular.tint(couleur…))` → matière en verre
///   translucide légèrement colorée à l'accent de la section, qui donne de
///   la profondeur au lieu d'une surface plate opaque.
/// - **Icône** : badge circulaire plein `couleur.gradient`, SF Symbol blanc.
/// - **Texte** : titre en couleur d'accent, sous-titre en `.secondary`.
/// - **Chevron** : `chevron.right` teinté à droite → affordance de nav.
///
/// Layout **horizontal compact** : icône à gauche, titre + sous-titre au
/// centre, chevron à droite. Hauteur intrinsèque (plus de `maxHeight:
/// .infinity` qui étirait la carte et laissait un grand vide au milieu).
/// Style de bouton des cartes du Journal — assombrit légèrement la carte
/// pendant l'appui, comme la carte « Analyse du coucher ».
///
/// `.buttonStyle(.plain)` seul ne produit pas cet effet ici : le verre des
/// cartes est rendu dans un `GlassEffectContainer`, hors de la chaîne
/// d'opacité à laquelle le style plain applique son feedback d'appui — la
/// carte restait donc totalement inerte sous le doigt. L'overlay est
/// explicite, et clippé à la forme de la carte.
struct StyleCarteJournal: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // L'état d'appui descend par l'environnement plutôt que par un
            // overlay : le verre est rendu par le `GlassEffectContainer` dans
            // sa propre couche, au-dessus de tout ce que le style empile
            // par-dessus le label. Seule la carte elle-même peut assombrir
            // sa matière, en teintant son propre `glassEffect`.
            .environment(\.carteJournalEnfoncee, configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(NiveauCarte.carte.forme)
    }
}

private struct CleCarteJournalEnfoncee: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` pendant l'appui sur la carte — posé par `StyleCarteJournal`,
    /// lu par `CarteSection` pour assombrir sa teinte de verre.
    var carteJournalEnfoncee: Bool {
        get { self[CleCarteJournalEnfoncee.self] }
        set { self[CleCarteJournalEnfoncee.self] = newValue }
    }
}

struct CarteSection: View {
    let icone: String
    let titre: String
    let sousTitre: String
    let couleur: Color

    @Environment(\.carteJournalEnfoncee) private var enfoncee

    /// Teinte du verre — assombrie à l'appui (mélange vers le noir, opacité
    /// renforcée) pour donner le même retour visuel que la carte
    /// « Analyse du coucher ».
    private var teinteVerre: Color {
        enfoncee
            ? couleur.mix(with: .black, by: 0.55).opacity(0.38)
            : couleur.opacity(0.18)
    }

    var body: some View {
        HStack(spacing: 16) {
            iconeBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(titre)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(couleur)

                Text(sousTitre)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(couleur.opacity(0.55))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        // `minHeight` fixe : le sous-titre peut faire 1 ou 2 lignes selon le
        // compteur du jour (« Aucune activité » vs « 3 médications
        // enregistrées aujourd'hui ») — sans plancher commun les trois
        // cartes n'avaient pas la même hauteur.
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        // Verre translucide teinté à l'accent de la section : profondeur
        // Liquid Glass tout en gardant l'identité couleur de chaque section.
        .surfaceCarteVerre(teinte: teinteVerre)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre), \(sousTitre)")
        .accessibilityAddTraits(.isButton)
    }

    /// Badge circulaire plein (dégradé de l'accent) avec l'icône SF Symbol
    /// blanche — contraste franc sur le verre teinté de la carte.
    private var iconeBadge: some View {
        Image(systemName: icone)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(couleur.gradient, in: Circle())
            .accessibilityHidden(true)
    }

}

#Preview {
    VStack(spacing: 16) {
        CarteSection(
            icone: "fork.knife",
            titre: "Repas",
            sousTitre: "3 repas enregistrés aujourd'hui",
            couleur: .blue
        )
        CarteSection(
            icone: "figure.run",
            titre: "Activités sportives",
            sousTitre: "Aucune activité aujourd'hui",
            couleur: .orange
        )
        CarteSection(
            icone: "syringe",
            titre: "Médications",
            sousTitre: "Aucune médication aujourd'hui",
            couleur: .purple
        )
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
