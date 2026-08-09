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

    /// Pastille de résultat accolée au titre — `nil` quand l'événement n'a
    /// rien à juger (une correction d'insuline, un aliment pré-sport) ou
    /// quand l'écran appelant n'a pas de notion de verdict (détail de nuit).
    var pastille: Pastille? = nil

    /// Encart de détail déplié **sous** la ligne. Réservé au geste explicite
    /// de l'utilisateur : le laisser suivre la surbrillance ferait sauter la
    /// mise en page à chaque déplacement du curseur sur la courbe.
    var encart: () -> AnyView? = { nil }

    /// Étiquette compacte de résultat : texte + teinte porteuse de sens.
    struct Pastille {
        let texte: String
        let couleur: Color
        let fond: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ligne
            if let encart = encart() {
                encart
                    .padding(.leading, 48)
                    .padding(.trailing, 14)
                    .padding(.bottom, 12)
            }
        }
        // Forme explicite : sans elle, iOS 26 fait adopter au fond la forme
        // concentrique du conteneur, et la surbrillance d'une ligne du milieu
        // s'arrondissait sur ses quatre coins au lieu de remplir la largeur.
        // La découpe des coins réellement extérieurs est le travail du
        // `clipShape` de la carte, pas celui de la ligne.
        .background(actif ? couleur.opacity(0.12) : .clear, in: Rectangle())
        .animation(.easeOut(duration: 0.2), value: actif)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre), \(sousTitre), \(detail)")
    }

    private var ligne: some View {
        HStack(spacing: 12) {
            Image(systemName: icone)
                .font(.subheadline)
                .foregroundStyle(couleur)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                // `flexible` plutôt qu'un `HStack` simple : les libellés de
                // verdict les plus longs (« Chute non enrayée ») passent à la
                // ligne au lieu de comprimer le titre.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        titreTexte
                        pastilleVue
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        titreTexte
                        pastilleVue
                    }
                }
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
    }

    private var titreTexte: some View {
        Text(titre)
            .font(.subheadline)
            .foregroundStyle(enAlerte ? .red : .primary)
    }

    @ViewBuilder
    private var pastilleVue: some View {
        if let pastille {
            Text(pastille.texte)
                .font(.caption2.weight(.medium))
                .foregroundStyle(pastille.couleur)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(pastille.fond, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

// MARK: - Carte englobante

extension View {

    /// Applique l'habillage commun d'une liste d'événements sous une courbe :
    /// surface de carte opaque et découpe aux coins arrondis.
    ///
    /// Fond opaque et non plus Liquid Glass : sous un graphique, le verre
    /// laissait transparaître la courbe et les points derrière les lignes,
    /// ce qui brouillait la lecture d'une liste déjà dense.
    ///
    /// Le clip n'est pas cosmétique — la surbrillance d'une ligne active est
    /// un fond rectangulaire pleine largeur, qui déborderait sinon des coins
    /// sur la première et la dernière ligne. `surfaceCarte` l'applique
    /// **après** le fond, dans le bon ordre.
    func carteListeEvenements() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCarte()
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        LigneEvenementCourbe(
            icone: "fork.knife",
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
#endif
