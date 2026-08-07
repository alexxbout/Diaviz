//
//  LigneEvenementCourbe.swift
//  diaviz
//

import SwiftUI

/// Ligne d'un événement listé sous une courbe glycémique parcourable —
/// icône teintée, titre, contexte, valeur chiffrée à droite.
///
/// Partagée par les écrans qui racontent « une courbe + les événements qui
/// l'expliquent » : détail d'activité sportive (`FriseSeanceSportive`) et
/// détail d'une soirée (`SheetDetailSoiree`). Ces listes se lisent de la
/// même façon, elles doivent avoir exactement la même forme.
///
/// La ligne ne connaît ni le modèle d'événement de l'appelant ni le type de
/// son axe temporel (`Date` côté nuit, `TimeInterval` côté sport) : chaque
/// écran mappe ses propres données vers ces quelques champs d'affichage.
struct LigneEvenementCourbe: View {

    let icone: String
    let couleur: Color
    let titre: String
    /// Contexte sous le titre — heure, phase, mentions particulières.
    let sousTitre: String
    /// Valeur chiffrée à droite (dose, glucides, glycémie…).
    let detail: String

    /// Événement pointé par le curseur de la courbe — surbrillance de liaison.
    var actif: Bool = false
    /// Titre affiché en rouge (hypoglycémie).
    var enAlerte: Bool = false
    /// Affiche un chevron : la ligne mène à un écran plus détaillé.
    var afficheChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icone)
                .font(.subheadline)
                .foregroundStyle(couleur)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(titre)
                    .font(.subheadline)
                    .foregroundStyle(enAlerte ? .red : .primary)
                Text(sousTitre)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()

            if afficheChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(actif ? couleur.opacity(0.12) : .clear)
        .animation(.easeOut(duration: 0.2), value: actif)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre), \(sousTitre), \(detail)")
    }
}

// MARK: - Carte englobante

extension View {

    /// Applique l'habillage commun d'une liste d'événements sous une courbe :
    /// matière Liquid Glass et découpe aux coins arrondis.
    ///
    /// Le clip n'est pas cosmétique — la surbrillance d'une ligne active est
    /// un fond rectangulaire pleine largeur, qui déborderait sinon des coins
    /// sur la première et la dernière ligne. Il doit rester **après** le
    /// verre, sinon la surbrillance passe par-dessus la découpe.
    func carteListeEvenements(rayon: CGFloat = 14) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: rayon, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 0) {
        LigneEvenementCourbe(
            icone: "leaf.fill",
            couleur: .green,
            titre: "Glucides pré-sport",
            sousTitre: "Pomme",
            detail: "17g"
        )
        Divider().padding(.leading, 46)
        LigneEvenementCourbe(
            icone: "syringe",
            couleur: .blue,
            titre: "Correction",
            sousTitre: "15h53 · 7 min avant",
            detail: "10,5 u",
            actif: true
        )
        Divider().padding(.leading, 46)
        LigneEvenementCourbe(
            icone: "exclamationmark.triangle.fill",
            couleur: .red,
            titre: "Hypo",
            sousTitre: "16h50 · 50 min d'effort",
            detail: "64",
            enAlerte: true
        )
    }
    .carteListeEvenements()
    .padding()
    .background(Color(.systemGroupedBackground))
}
