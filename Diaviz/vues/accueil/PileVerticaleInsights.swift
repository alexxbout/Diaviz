//
//  PileVerticaleInsights.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import SwiftUI

/// Pile verticale de cartes d'observations — la carte du dessus est
/// fully visible et interactive (drag vertical), les cartes derrière
/// pointent **dessous** avec scale/opacity dégradés pour signaler
/// qu'il y en a d'autres.
///
/// Au swipe (drag vertical past seuil), la carte du dessus part en
/// transition `.move(edge: .bottom)` (= passe dessous), `indexActif`
/// avance dans un spring, et SwiftUI remonte automatiquement les
/// cartes derrière à leurs nouvelles positions (animation pilotée
/// par l'identité stable de chaque insight dans le ZStack).
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
    private let seuilSwipe: CGFloat = 80

    /// Distance verticale au-delà de laquelle le dismiss est
    /// déclenché **automatiquement** pendant le drag (sans attendre
    /// le release). Cale aussi le drag max — la carte file en
    /// dessous dès qu'on atteint cette distance.
    private let seuilAutoDismiss: CGFloat = 120

    var body: some View {
        ZStack(alignment: .top) {
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
        let decalageBase = CGFloat(item.position) * decalageY
        let drag: CGFloat = estTop ? glissementY : 0
        let echelleBase = 1 - CGFloat(item.position) * echelleParCarte
        let opacite = 1 - Double(item.position) * opaciteParCarte

        // Léger scale-down de la carte du dessus pendant le drag —
        // donne un feedback tactile "je tiens la carte". Progresse
        // linéairement avec la distance de drag, capé à -6% à 200pt.
        let progressionDrag = estTop ? min(1, abs(glissementY) / 200) : 0
        let echelle = echelleBase * (1 - progressionDrag * 0.06)

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
    /// nouvelle carte arrière apparaît doucement), suppression en
    /// `.move(edge: .bottom)` + opacity (la carte du dessus glisse
    /// vers le bas et fait dessous quand on swipe). Extraite d'un
    /// modifier inline pour soulager le type-checker.
    private var transitionCarte: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Pendant l'animation de dismiss, on ignore les
                // updates : la carte est déjà partie.
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
                // l'infini, la carte file en dessous).
                if abs(value.translation.height) > seuilAutoDismiss {
                    declenchementDismiss()
                }
            }
            .onEnded { value in
                guard !enCoursDeDismiss else { return }

                if abs(value.translation.height) > seuilSwipe {
                    declenchementDismiss()
                } else {
                    // Pas assez loin → snap back élastique.
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        glissementY = 0
                    }
                }
            }
    }

    /// Anime le passage de la carte du dessus en dessous de la pile.
    /// Pose le verrou `enCoursDeDismiss` pour bloquer les ré-entrées
    /// du gesture pendant l'animation, libère le verrou au complétion.
    private func declenchementDismiss() {
        enCoursDeDismiss = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            indexActif = (indexActif + 1) % insights.count
            glissementY = 0
        } completion: {
            enCoursDeDismiss = false
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
