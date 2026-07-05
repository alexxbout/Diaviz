//
//  PillsCoucher.swift
//  diaviz
//
//  Created by Alexandre on 04/07/2026.
//

import SwiftUI

/// Une pill du sélecteur : SF Symbol + libellé + couleur d'accent de la section.
struct PillCoucher: Identifiable, Equatable {
    let id: Int
    let icone: String
    let titre: String
    let couleur: Color
}

/// Sélecteur horizontal à pills **draguables** pour la page « Analyse du
/// coucher ». Épuré : Liquid Glass non tinté (`.regular`), sans bordure ni
/// fond de couleur — seuls l'icône et le titre portent la couleur de la
/// section. La pill sélectionnée est centrée, les voisines dépassent de part
/// et d'autre et sont atténuées.
///
/// Interaction : glissement horizontal → défilement suivi du doigt, snap sur
/// la pill la plus proche au relâchement (avec inertie, ±1 cran max) ; un tap
/// sélectionne la pill sous le doigt. Le composant est posé **fixe** au-dessus
/// du contenu scrollable de la page.
struct PillsCoucher: View {

    @Binding var selection: Int
    let items: [PillCoucher]

    @State private var dragOffset: CGFloat = 0

    /// Hauteur du composant — exposée pour que la page hôte réserve l'espace
    /// (padding haut du contenu) quand les pills flottent en overlay.
    static let hauteur: CGFloat = 72
    private static let hauteurPill: CGFloat = 54
    private static let fractionLargeurPill: CGFloat = 0.62
    private static let espacement: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let largeur = geo.size.width
            let largeurPill = largeur * Self.fractionLargeurPill
            let pas = largeurPill + Self.espacement
            let position = positionContinue(largeur: largeur, largeurPill: largeurPill, pas: pas)

            HStack(spacing: Self.espacement) {
                ForEach(items) { item in
                    pill(item, largeurPill: largeurPill, position: position)
                }
            }
            .frame(width: largeur, alignment: .leading)
            .offset(x: offsetStrip(largeur: largeur, largeurPill: largeurPill, pas: pas))
            .frame(width: largeur, height: Self.hauteur)
            .contentShape(Rectangle())
            .gesture(dragStrip(largeur: largeur, largeurPill: largeurPill, pas: pas))
        }
        .frame(height: Self.hauteur)
        .accessibilityElement(children: .contain)
    }

    private func pill(_ item: PillCoucher, largeurPill: CGFloat, position: Double) -> some View {
        // Proximité 0…1 : 1 quand la pill est centrée, 0 à un cran.
        let proximite = max(0, 1 - abs(position - Double(item.id)))
        return HStack(spacing: 8) {
            Image(systemName: item.icone)
                .font(.body.weight(.semibold))
            Text(item.titre)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(item.couleur.opacity(0.45 + 0.55 * proximite))
        .frame(width: largeurPill, height: Self.hauteurPill)
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .accessibilityAddTraits(item.id == selection ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(item.titre)
        .accessibilityAction { selectionner(item.id) }
    }

    // MARK: - Géométrie (pill sélectionnée centrée)

    private func offsetBase(largeur: CGFloat, largeurPill: CGFloat) -> CGFloat {
        (largeur - largeurPill) / 2
    }

    private func offsetStrip(largeur: CGFloat, largeurPill: CGFloat, pas: CGFloat) -> CGFloat {
        let base = offsetBase(largeur: largeur, largeurPill: largeurPill)
        let brut = base - CGFloat(selection) * pas + dragOffset
        let minOffset = base - CGFloat(items.count - 1) * pas
        return min(base, max(minOffset, brut))
    }

    private func positionContinue(largeur: CGFloat, largeurPill: CGFloat, pas: CGFloat) -> Double {
        guard pas > 0 else { return Double(selection) }
        let base = offsetBase(largeur: largeur, largeurPill: largeurPill)
        return Double((base - offsetStrip(largeur: largeur, largeurPill: largeurPill, pas: pas)) / pas)
    }

    // MARK: - Gestes

    private func dragStrip(largeur: CGFloat, largeurPill: CGFloat, pas: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { valeur in
                dragOffset = valeur.translation.width
            }
            .onEnded { valeur in
                let dx = valeur.translation.width
                let dy = valeur.translation.height
                if abs(dx) < 6, abs(dy) < 6 {
                    // Tap : sélectionne la pill sous le doigt.
                    let offset = offsetStrip(largeur: largeur, largeurPill: largeurPill, pas: pas)
                    let idx = ((valeur.startLocation.x - offset - largeurPill / 2) / pas).rounded()
                    selectionner(min(items.count - 1, max(0, Int(idx))))
                    dragOffset = 0
                    return
                }
                // Snap à la pill la plus proche (inertie, ±1 cran par geste).
                let projete = valeur.predictedEndTranslation.width
                let crans = max(-1, min(1, Int((-projete / pas).rounded())))
                let cible = min(items.count - 1, max(0, selection + crans))
                withAnimation(.snappy(duration: 0.30, extraBounce: 0.03)) {
                    selection = cible
                    dragOffset = 0
                }
            }
    }

    private func selectionner(_ index: Int) {
        withAnimation(.snappy(duration: 0.30, extraBounce: 0.03)) {
            selection = index
        }
    }
}

// MARK: - Aperçu

#Preview("Pills coucher") {
    struct Demo: View {
        @State private var selection = 0
        var body: some View {
            VStack(spacing: 0) {
                PillsCoucher(
                    selection: $selection,
                    items: [
                        PillCoucher(id: 0, icone: "syringe.fill", titre: "Tendance basale", couleur: .indigo),
                        PillCoucher(id: 1, icone: "bed.double.fill", titre: "Endormissement", couleur: .teal),
                        PillCoucher(id: 2, icone: "plusminus", titre: "Corrections", couleur: .orange),
                    ]
                )
                Spacer()
                Text("Page \(selection)").font(.title.bold())
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    return Demo()
}
