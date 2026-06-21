//
//  PileVerticaleInsights.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Pile verticale de cartes d'observations — la carte active est en
/// **bas** de la pile, fully visible et interactive (drag vertical) ;
/// les cartes suivantes pointent **au-dessus** d'elle avec scale/opacity
/// dégradés pour signaler qu'il y en a d'autres. On lit la pile de bas
/// en haut.
///
/// Au swipe (drag vertical past seuil), la carte active part en
/// transition `.move(edge: .top)` (= file vers le haut, dans la pile),
/// `indexActif` avance dans un spring, et SwiftUI redescend
/// automatiquement les cartes suivantes à leurs nouvelles positions
/// (animation pilotée par l'identité stable de chaque insight dans le
/// ZStack).
///
/// Toute l'animation tient en un seul `withAnimation` — pas de
/// chaînage en deux temps qui faisait drifter le premier essai.
struct PileVerticaleInsights: View {

    let insights: [Insight]
    @Binding var indexActif: Int

    /// Translation Y courante issue du drag user. Appliquée
    /// uniquement à la carte du dessus.
    @State private var glissementY: CGFloat = 0

    /// Verrou actif pendant l'animation de dismiss — empêche le
    /// `DragGesture` de re-déclencher l'action plusieurs fois (le
    /// doigt peut continuer à bouger pendant que la carte file).
    @State private var enCoursDeDismiss: Bool = false

    // MARK: Paramètres visuels de la pile

    /// Nombre de cartes empilées rendues simultanément (top inclus).
    private let cartesVisibles: Int = 3
    /// Décalage Y entre cartes — assez grand pour qu'on voit
    /// clairement les cartes derrière (et pas juste un bord).
    private let decalageY: CGFloat = 26
    /// Réduction d'échelle par carte derrière (6% chacune).
    private let echelleParCarte: CGFloat = 0.06
    /// Réduction d'opacité par carte derrière (22% chacune).
    private let opaciteParCarte: Double = 0.22
    /// Hauteur fixe d'une carte — calée pour 2 lignes de message +
    /// un micro-visuel de 30pt.
    private let hauteurCarte: CGFloat = 180
    /// Distance verticale au-delà de laquelle un drag relâché est
    /// considéré comme un swipe validé.
    private let seuilSwipe: CGFloat = 64

    /// Distance verticale au-delà de laquelle le dismiss est
    /// déclenché **automatiquement** pendant le drag (sans attendre
    /// le release). Cale aussi le drag max — la carte file en
    /// dessous dès qu'on atteint cette distance.
    private let seuilAutoDismiss: CGFloat = 100

    var body: some View {
        // Alignement bas : la carte active (position 0) s'ancre en bas de
        // la pile, les suivantes débordent vers le haut (offset négatif).
        ZStack(alignment: .bottom) {
            ForEach(pileVisible) { item in
                carteEmpilee(item)
            }
        }
        .frame(height: hauteurTotale)
    }

    /// Hauteur totale réservée à la pile : carte top + décalages
    /// cumulés des cartes derrière (pour que la dernière carte
    /// peek sans être coupée par un clip de frame).
    private var hauteurTotale: CGFloat {
        hauteurCarte + CGFloat(cartesVisibles - 1) * decalageY
    }

    /// Slice de la pile actuellement rendue, indexée cycliquement
    /// pour ne jamais être vide (4 insights mais 3 cartes visibles →
    /// l'insight de la 4e prend sa place via le modulo).
    private var pileVisible: [PileItem] {
        let n = min(cartesVisibles, insights.count)
        return (0..<n).map { offset in
            let index = (indexActif + offset) % insights.count
            return PileItem(insight: insights[index], position: offset)
        }
    }

    @ViewBuilder
    private func carteEmpilee(_ item: PileItem) -> some View {
        let estTop = item.position == 0
        // Offset **négatif** : les cartes derrière montent au-dessus de la
        // carte active (ancrée en bas), pour une lecture de bas en haut.
        let decalageBase = -CGFloat(item.position) * decalageY
        let drag: CGFloat = estTop ? glissementY : 0
        let echelleBase = 1 - CGFloat(item.position) * echelleParCarte
        let opacite = 1 - Double(item.position) * opaciteParCarte

        // Scale-down de la carte du dessus pendant le drag — donne
        // un feedback tactile "je tiens la carte". Progresse
        // linéairement avec la distance de drag, capé à -15% à 175pt.
        let progressionDrag = estTop ? min(1, abs(glissementY) / 175) : 0
        let echelle = echelleBase * (1 - progressionDrag * 0.15)

        CarteInsight(insight: item.insight)
            .frame(height: hauteurCarte)
            .offset(y: decalageBase + drag)
            .scaleEffect(echelle)
            .opacity(opacite)
            .zIndex(Double(-item.position))
            // `.contentShape` rend **toute la surface** de la carte
            // hit-testable pour le drag — sans ça, certaines zones
            // (background translucide entre les éléments texte)
            // ne déclenchaient pas la gesture.
            .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .gesture(estTop ? swipeGesture : nil)
            .accessibilityHidden(!estTop)
            .transition(transitionCarte)
    }

    /// Transition appliquée aux cartes : insertion en fondu (la
    /// nouvelle carte arrière apparaît doucement en haut de la pile),
    /// suppression en `.move(edge: .top)` + opacity (la carte active
    /// file vers le haut, dans la pile, quand on swipe). Extraite d'un
    /// modifier inline pour soulager le type-checker.
    private var transitionCarte: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Pendant qu'un dismiss est en cours (doigt toujours
                // posé sur l'écran), on ignore les updates pour que
                // la nouvelle carte top ne se mette pas à suivre le
                // doigt et ne soit pas re-dismissée en chaîne.
                guard !enCoursDeDismiss else { return }

                // Filtre directionnel — on n'absorbe le drag que s'il
                // est principalement vertical, sinon on laisse les
                // gestures horizontaux passer (rien à intercepter ici
                // mais on évite d'embarquer le ScrollView parent).
                guard abs(value.translation.height) > abs(value.translation.width) else { return }

                glissementY = value.translation.height

                // Auto-dismiss au-delà du gros seuil — pendant le
                // drag, sans attendre le release. Plafonne de fait
                // la distance de drag visible (au lieu d'aller à
                // l'infini, la carte file en dessous). Le verrou est
                // posé ici et ne sera libéré qu'au `.onEnded` (release
                // du doigt) — c'est ce qui empêche le re-déclenchement
                // en chaîne sur la nouvelle carte top.
                if abs(value.translation.height) > seuilAutoDismiss {
                    enCoursDeDismiss = true
                    declenchementDismiss()
                }
            }
            .onEnded { value in
                // Cas 1 : auto-dismiss déjà déclenché pendant le drag.
                // On se contente de libérer le verrou — le release
                // arrive après la fin (probable) de l'animation, le
                // doigt est enfin levé, la mécanique peut reprendre.
                if enCoursDeDismiss {
                    enCoursDeDismiss = false
                    return
                }

                // Cas 2 : release au-delà du seuil "intentionnel" mais
                // sans avoir atteint l'auto-dismiss → dismiss classique.
                // Pas besoin de verrou : le gesture est en train de se
                // terminer, aucun `.onChanged` ne suivra.
                if abs(value.translation.height) > seuilSwipe {
                    declenchementDismiss()
                } else {
                    // Cas 3 : pas assez loin → snap back élastique.
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        glissementY = 0
                    }
                }
            }
    }

    /// Anime le passage de la carte du dessus en dessous de la pile.
    /// La gestion du verrou `enCoursDeDismiss` (pose / libération)
    /// est faite par les call-sites — ici on ne fait que l'animation.
    private func declenchementDismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            indexActif = (indexActif + 1) % insights.count
            glissementY = 0
        }
    }
}

// MARK: - Item interne

/// Wrapper interne pour le ForEach — porte l'identité de l'insight
/// (via son UUID) et sa position relative dans la pile, ce qui permet
/// à SwiftUI d'animer le mouvement quand un insight change de slot.
private struct PileItem: Identifiable {
    let insight: Insight
    let position: Int
    var id: UUID { insight.id }
}

// MARK: - Aperçus

#Preview("Pile verticale - 4 observations") {
    @Previewable @State var index = 0
    ScrollView {
        PileVerticaleInsights(insights: InsightsAccueilServiceMock.mockComplet(), indexActif: $index)
            .padding(.vertical, 16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Pile verticale - Sombre") {
    @Previewable @State var index = 0
    ScrollView {
        PileVerticaleInsights(insights: InsightsAccueilServiceMock.mockComplet(), indexActif: $index)
            .padding(.vertical, 16)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
