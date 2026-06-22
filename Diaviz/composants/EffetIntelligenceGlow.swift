//
//  EffetIntelligenceGlow.swift
//  diaviz
//
//  Created by Alexandre on 07/05/2026.
//

import SwiftUI

// MARK: - Modifier

/// Effet « glow Apple Intelligence » : 4 couches de `AngularGradient` strokées
/// sur une `InsettableShape`, avec différents `lineWidth` et flous, animées en
/// continu par régénération aléatoire des `stops`. Pure SwiftUI, pas de Metal.
///
/// S'applique en overlay sur n'importe quelle vue, autour d'une forme paramétrable
/// (typiquement la même `RoundedRectangle` que la carte sous-jacente).
///
/// Usage :
/// ```
/// MaCarte()
///     .glowIntelligence(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
/// ```
///
/// Le glow est non-interactif (`allowsHitTesting(false)`) — taps et gestures
/// passent au travers vers la vue sous-jacente.
struct EffetIntelligenceGlow<Forme: InsettableShape>: ViewModifier {

    let forme: Forme

    /// 4 jeux de stops indépendants — un par couche. Mis à jour à tour de rôle
    /// pour donner un effet organique (les 4 couches ne pulsent jamais en phase).
    @State private var stopsCouches: [[Gradient.Stop]] = GlowStops.initiales()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    couche(index: 0, lineWidth: 1.5, blur: 0)
                    couche(index: 1, lineWidth: 3,   blur: 5)
                    couche(index: 2, lineWidth: 6,   blur: 12)
                    couche(index: 3, lineWidth: 9,   blur: 20)
                }
                .compositingGroup()
                // Atténuation globale : 0.65 baisse l'éclat sans casser
                // l'effet (ajustable selon le contexte d'utilisation).
                .opacity(0.65)
                // Mask = anneau extérieur : un grand rectangle (frame étendu
                // de 60 pt par padding négatif) avec la forme punchée en
                // destinationOut. Résultat : le glow ne s'affiche QUE à
                // l'extérieur de la carte, jamais sur le texte.
                .mask {
                    ZStack {
                        Rectangle()
                            .padding(-60)
                        forme
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .allowsHitTesting(false)
            }
            .task {
                guard !reduceMotion else { return }
                // Une seule boucle qui met à jour une couche à la fois en
                // round-robin. Chaque couche s'anime sur 0.7 s avec un nouveau
                // tirage toutes les 0.25 s — les transitions se chevauchent et
                // produisent un mouvement continu.
                var indexCouche = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(0.25))
                    if Task.isCancelled { return }
                    withAnimation(.easeInOut(duration: 0.7)) {
                        stopsCouches[indexCouche] = GlowStops.nouveaux()
                    }
                    indexCouche = (indexCouche + 1) % stopsCouches.count
                }
            }
    }

    @ViewBuilder
    private func couche(index: Int, lineWidth: CGFloat, blur: CGFloat) -> some View {
        // `.stroke` (centré sur le bord) plutôt que `.strokeBorder` (intérieur)
        // : avec le mask extérieur appliqué plus haut, un strokeBorder serait
        // entièrement clippé. Avec stroke centré, la moitié extérieure passe
        // et produit un anneau lumineux sur le bord exact de la carte.
        forme
            .stroke(
                AngularGradient(
                    stops: stopsCouches[index],
                    center: .center
                ),
                lineWidth: lineWidth
            )
            .blur(radius: blur)
    }
}

// MARK: - Palette et génération de stops

/// Helpers extraits dans une enum non-générique pour pouvoir être appelés
/// dans l'initialisation par défaut de `@State` (`Self` n'est pas utilisable
/// dans ce contexte sur un type générique).
private enum GlowStops {

    /// Palette inspirée du gradient Apple Intelligence — violets, magentas,
    /// bleus saturés, et des touches d'or et de cyan pour la chaleur.
    static let palette: [Color] = [
        Color(red: 0.42, green: 0.27, blue: 0.96), // violet
        Color(red: 0.96, green: 0.27, blue: 0.71), // magenta
        Color(red: 0.27, green: 0.50, blue: 0.96), // bleu vif
        Color(red: 0.96, green: 0.71, blue: 0.27), // or chaud
        Color(red: 0.27, green: 0.85, blue: 0.96), // cyan
        Color(red: 0.71, green: 0.27, blue: 0.96), // pourpre
    ]

    /// Tire 6 stops avec positions aléatoires triées — couvre toujours toute
    /// la circonférence de l'`AngularGradient` pour éviter les zones « mortes ».
    static func nouveaux() -> [Gradient.Stop] {
        palette
            .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
            .sorted { $0.location < $1.location }
    }

    static func initiales() -> [[Gradient.Stop]] {
        (0..<4).map { _ in nouveaux() }
    }
}

// MARK: - Extensions d'application

extension View {
    /// Applique un glow Apple-Intelligence-style autour de la vue, dessiné sur
    /// le contour de la forme passée en paramètre. La forme doit correspondre
    /// à celle de la carte sous-jacente (mêmes corner radius, même style) pour
    /// que le glow épouse parfaitement les bords.
    ///
    /// Le composant parent doit prévoir un padding extérieur d'environ 20 pt
    /// pour que les couches floues (jusqu'à ~18 pt de blur) ne soient pas
    /// rognées.
    func glowIntelligence<F: InsettableShape>(in forme: F) -> some View {
        modifier(EffetIntelligenceGlow(forme: forme))
    }
}

// MARK: - Aperçus

#Preview("Glow autour d'une carte sombre") {
    VStack(spacing: 24) {
        Text("Phrase générée par Apple Intelligence — le glow signale la nature IA du contenu.")
            .font(.body)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .glowIntelligence(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .padding(36)
    .background(Color(.systemGroupedBackground))
}

#Preview("Glow autour d'une capsule") {
    Text("Pilule IA")
        .font(.headline)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: .capsule)
        .glowIntelligence(in: Capsule())
        .padding(40)
        .background(Color(.systemGroupedBackground))
}

#Preview("Glow — mode sombre") {
    Text("Hier, belle journée avec un score 92 et aucune hypoglycémie.")
        .font(.body)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .glowIntelligence(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(24)
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
