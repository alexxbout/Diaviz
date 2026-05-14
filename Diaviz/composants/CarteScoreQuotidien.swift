//
//  CarteScoreQuotidien.swift
//  diaviz
//
//  Created by Alexandre on 06/05/2026.
//

import SwiftUI
import Charts

// MARK: - Modèles publics

/// Données affichées par `CarteScoreQuotidien`. Partagée entre les
/// variants de style pour garantir une cohérence d'affichage.
struct ContenuCarteScore: Sendable, Equatable {
    /// Score sur 100 — `nil` quand la couverture CGM est insuffisante.
    let score: Int?
    /// Date du score affiché (le dernier élément d'`historique`).
    let date: Date
    /// 7 derniers scores, du plus ancien au plus récent. Les valeurs
    /// `nil` sont rendues en barres atténuées.
    let historique: [Int?]
}

/// Style visuel de la carte. La variante `.gradient` reprend la teinte
/// du mesh du cercle en fond de carte, et passe textes / bulle / barres
/// en blanc avec glass effect.
enum StyleCarteScore: Sendable, CaseIterable {
    case sobre
    case gradient
}

// MARK: - Vue principale

/// Carte « score quotidien » — résumé glycémique de la veille, style
/// Apple Santé : barre de titre avec icône + chevron, puis cercle
/// dégradé portant le chiffre, qualificatif court, et mini-graphique
/// en barres des 7 derniers jours. Existe en deux variants visuels
/// (voir `StyleCarteScore`).
struct CarteScoreQuotidien: View {

    let contenu: ContenuCarteScore
    var style: StyleCarteScore = .sobre
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                ligneTitre
                ligneContenu
            }
            .padding(16)
            .background(fondCarte)
            .overlay(bordureCarte)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelleAccessibilite)
        .accessibilityHint("Ouvre les détails du score")
    }

    /// Barre de titre style Apple Santé : icône tintée + titre tinté
    /// dans la teinte du score (sobre) ou en blanc (gradient), chevron
    /// à droite.
    private var ligneTitre: some View {
        HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(couleurTitre)
            Text("Score de la veille")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(couleurTitre)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(couleurChevron)
        }
    }

    private var ligneContenu: some View {
        HStack(spacing: 14) {
            CercleScore(score: contenu.score, style: style)

            Text(libelleQualitatif)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(couleurTexte)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            HistoriqueBarChart(
                historique: contenu.historique,
                scoreActuel: contenu.score,
                style: style
            )
            .accessibilityHidden(true)
        }
    }

    // MARK: Apparence dérivée du style

    @ViewBuilder
    private var fondCarte: some View {
        switch style {
        case .sobre:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        case .gradient:
            TimelineView(.animation) { contexte in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MeshScore.gradient(
                        pour: contenu.score,
                        phase: MeshScore.phase(date: contexte.date)
                    ))
            }
        }
    }

    @ViewBuilder
    private var bordureCarte: some View {
        switch style {
        case .sobre:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        case .gradient:
            // Pas de bordure : le mesh fournit déjà la délimitation visuelle.
            EmptyView()
        }
    }

    private var couleurTitre: Color {
        switch style {
        case .sobre:
            guard let score = contenu.score else { return .secondary }
            return CouleurScore.couleur(pour: score)
        case .gradient:
            return .white
        }
    }

    private var couleurTexte: Color {
        switch style {
        case .sobre:    return .primary
        case .gradient: return .white
        }
    }

    private var couleurChevron: Color {
        switch style {
        case .sobre:    return Color(.tertiaryLabel)
        case .gradient: return Color.white.opacity(0.75)
        }
    }

    /// Libellé qualitatif court affiché à droite du cercle. 5 paliers
    /// alignés sur les seuils visuels du projet.
    private var libelleQualitatif: String {
        guard let score = contenu.score else { return "Indisponible" }
        switch score {
        case 90...:    return "Très bonne"
        case 70..<90:  return "Bonne"
        case 50..<70:  return "Moyenne"
        case 30..<50:  return "Difficile"
        default:       return "Très difficile"
        }
    }

    private var libelleAccessibilite: String {
        if let score = contenu.score {
            return "Score d'hier : \(score) sur 100, journée \(libelleQualitatif.lowercased())"
        }
        return "Score d'hier indisponible"
    }
}

// MARK: - Couleur d'accent du score

/// Teinte continue alignée sur le mesh gradient : `hue` croît
/// linéairement de 0 (rouge, score 0) à 0.33 (vert, score 100). Le titre,
/// la dernière barre de l'historique et l'ombre du cercle (variante
/// sobre) utilisent tous cette même teinte pour rester raccord.
///
/// Internal (pas private) parce que d'autres composants du module
/// (ex. `SheetScoreMatin`) en dépendent pour rester visuellement
/// cohérents avec la carte.
enum CouleurScore {
    static func hue(pour score: Int) -> Double {
        let borne = Double(min(100, max(0, score)))
        return (borne / 100.0) * 0.33
    }

    /// Couleur pleine d'accent — saturation/brightness calibrées pour
    /// rester lisibles en petit (titre 15pt, barre 5pt de large).
    static func couleur(pour score: Int) -> Color {
        Color(hue: hue(pour: score), saturation: 0.85, brightness: 0.80)
    }
}

// MARK: - Mesh gradient partagé

/// Constructeur du `MeshGradient` partagé entre :
///   - le cercle de la variante sobre (où il remplit la bulle)
///   - le fond de carte de la variante gradient (où il remplit la carte)
///
/// Centralisé ici pour garantir une cohérence parfaite entre les deux
/// usages — si on retouche les couleurs ou les points, les deux suivent.
///
/// Internal (pas private) parce que `SheetScoreMatin` réutilise le
/// même gradient pour son grand cercle 120pt.
enum MeshScore {

    /// Période de la boucle d'animation, en secondes. La motion est
    /// composée de plusieurs cycles (orbites Lissajous des points + onde
    /// chromatique traversant le mesh) ; cette période est la base que
    /// les fréquences individuelles multiplient.
    static let dureeBoucle: Double = 7.0

    /// Convertit une date en phase angulaire (en radians) pour alimenter
    /// l'orbite des points intérieurs et l'onde chromatique. À appeler
    /// depuis un `TimelineView(.animation)` pour rester synchro avec le
    /// refresh rate de l'écran.
    ///
    /// **Pas de wrap** : on laisse la phase croître indéfiniment, les
    /// fonctions trig gèrent la périodicité d'elles-mêmes. Wrapper à 2π
    /// créerait des sauts visibles puisque les fréquences (0.5, 0.8, 1.3,
    /// ...) ne sont pas des multiples entiers de la période de base —
    /// au moment du wrap, `cos(freq · 2π)` ne vaudrait pas `cos(0)`.
    /// La précision Double absorbe sans problème les ~10⁹ secondes
    /// depuis la date de référence.
    static func phase(date: Date) -> Double {
        date.timeIntervalSinceReferenceDate / dureeBoucle * 2 * .pi
    }

    /// Mesh 4×4 (16 points). Le passage de 3×3 à 4×4 double la densité
    /// d'interpolation : chaque transition coin↔centre traverse un
    /// point intermédiaire, ce qui élimine les "spots" sombres visibles
    /// dans la grille 3×3 et permet aux courants chaud/froid de dessiner
    /// de vraies courbes plutôt que des transitions rectilignes.
    ///
    /// **Périmètre figé / intérieur animé** : les 12 points du périmètre
    /// (indices 0-3, 4, 7, 8, 11, 12-15) restent strictement sur les
    /// bords (y=0/1, x=0/1) — c'est ce qui garantit que la silhouette
    /// de la rounded-rect / du cercle ne se déforme pas. Seuls les
    /// **4 points intérieurs** (indices 5, 6, 9, 10) bougent.
    ///
    /// Chaque point intérieur trace une **Lissajous** : fréquences X et Y
    /// distinctes (et différentes d'un point à l'autre) → les orbites ne
    /// se referment pas sur elles-mêmes et les 4 points dérivent en/hors
    /// de phase indéfiniment. Plus de symétrie rotationnelle perceptible,
    /// la motion paraît organique au lieu de "roue qui tourne".
    static func points(phase p: Double = 0) -> [SIMD2<Float>] {
        // Amplitudes serrées sur l'horizontal (motion visible) et la
        // verticale (gap minimal 0.08 entre rangées 1/2 garanti).
        let ampX: Float = 0.09
        let ampY: Float = 0.05
        let t = Float(p)
        func lissajous(
            _ base: SIMD2<Float>,
            _ freqX: Float,
            _ freqY: Float,
            _ dephasage: Float
        ) -> SIMD2<Float> {
            SIMD2(
                base.x + ampX * cos(freqX * t + dephasage),
                base.y + ampY * sin(freqY * t + dephasage)
            )
        }
        return [
            // Rangée 0 (haut) — y = 0 strict
            SIMD2(0.00, 0.00), SIMD2(0.33, 0.00), SIMD2(0.67, 0.00), SIMD2(1.00, 0.00),
            // Rangée 1 — bords figés, intérieurs en Lissajous distinctes
            SIMD2(0.00, 0.32),
                lissajous(SIMD2(0.40, 0.42), 1.0, 1.3, 0),
                lissajous(SIMD2(0.60, 0.30), 0.8, 1.1, .pi / 2),
                SIMD2(1.00, 0.36),
            // Rangée 2 — bords figés, intérieurs en Lissajous distinctes
            SIMD2(0.00, 0.64),
                lissajous(SIMD2(0.30, 0.62), 1.2, 0.9, .pi),
                lissajous(SIMD2(0.70, 0.72), 0.9, 1.4, 3 * .pi / 2),
                SIMD2(1.00, 0.68),
            // Rangée 3 (bas) — y = 1 strict
            SIMD2(0.00, 1.00), SIMD2(0.33, 1.00), SIMD2(0.67, 1.00), SIMD2(1.00, 1.00),
        ]
    }

    static func gradient(pour score: Int?, phase: Double = 0) -> MeshGradient {
        let pts = points(phase: phase)
        guard let score else {
            return MeshGradient(
                width: 4,
                height: 4,
                points: pts,
                colors: nuancesGrises,
                colorSpace: .perceptual
            )
        }
        let teinte = CouleurScore.hue(pour: score)
        return MeshGradient(
            width: 4,
            height: 4,
            points: pts,
            colors: colors(hue: teinte, phase: phase),
            colorSpace: .perceptual
        )
    }

    /// 16 stops organisés en **X chaud/froid** + **onde diagonale animée** :
    ///
    ///   - **Base statique** : coins TL/BR chauds (`+0.028`), coins TR/BL
    ///     froids (`-0.028`). Les intérieurs ont un offset réduit (`±0.003`)
    ///     pour éviter la "boundary" nette qui apparaissait avec ±0.014 :
    ///     le centre n'est plus polarisé, seuls les coins portent une
    ///     signature chromatique forte.
    ///   - **Onde traveling** : une sinusoïde traverse le mesh en
    ///     diagonale TL→BR avec une période deux fois plus lente que les
    ///     orbites des points. Chaque stop voit sa hue glisser dans le
    ///     temps — les courants chaud/froid coulent au lieu de tourner
    ///     en rond.
    ///
    /// **Brightness resserrée** dans [0.80, 0.88] — Δ0.08 au lieu du
    /// Δ0.29 de la version 3×3, qui plaquait des taches sombres aux
    /// coins. Le texte blanc reste lisible grâce à la saturation
    /// élevée + ombre portée.
    private static func colors(hue h: Double, phase p: Double = 0) -> [Color] {
        // Base statique : coins fortement marqués, intérieurs presque
        // neutres → le X chaud/froid n'a plus de frontière nette au centre.
        let dhStatic: [Double] = [
            +0.028, +0.006, -0.006, -0.028,
            +0.018, +0.003, -0.003, -0.018,
            -0.018, -0.003, +0.003, +0.018,
            -0.028, -0.006, +0.006, +0.028,
        ]
        // Onde diagonale animée — fréquence 0.5× les orbites des points
        // pour créer des cycles de drift décorrélés de la motion géométrique.
        let dhWaveAmp: Double = 0.012
        let dhWave: [Double] = (0..<16).map { i in
            let col = Double(i % 4) / 3.0
            let row = Double(i / 4) / 3.0
            return dhWaveAmp * sin(0.5 * p + (col + row) * .pi)
        }
        let dh: [Double] = (0..<16).map { dhStatic[$0] + dhWave[$0] }
        // Saturation — coins légèrement plus saturés que le centre pour
        // garder de la profondeur chromatique sans noircir.
        let saturations: [Double] = [
            0.88, 0.86, 0.86, 0.88,
            0.86, 0.84, 0.84, 0.86,
            0.86, 0.84, 0.84, 0.86,
            0.88, 0.86, 0.86, 0.88,
        ]
        // Brightness resserrée [0.80, 0.88] — fini les coins sombres,
        // le mesh reste lumineux et homogène, et le texte blanc tient.
        let brightnesses: [Double] = [
            0.80, 0.82, 0.82, 0.80,
            0.82, 0.88, 0.88, 0.82,
            0.82, 0.88, 0.88, 0.82,
            0.80, 0.82, 0.82, 0.80,
        ]
        return (0..<16).map { i in
            Color(
                hue: hueWrap(h + dh[i]),
                saturation: saturations[i],
                brightness: brightnesses[i]
            )
        }
    }

    /// Replie une hue éventuellement négative ou > 1 dans [0, 1).
    private static func hueWrap(_ h: Double) -> Double {
        let v = h.truncatingRemainder(dividingBy: 1.0)
        return v < 0 ? v + 1.0 : v
    }

    /// Variantes de gris pour le cas `score == nil` — même structure
    /// que `colors(hue:)` : highlight central léger, coins moins sombres
    /// qu'en 3×3 pour rester cohérent avec le mesh coloré. 16 stops.
    private static let nuancesGrises: [Color] = [
        Color(white: 0.72), Color(white: 0.78), Color(white: 0.78), Color(white: 0.72),
        Color(white: 0.78), Color(white: 0.90), Color(white: 0.90), Color(white: 0.78),
        Color(white: 0.78), Color(white: 0.90), Color(white: 0.90), Color(white: 0.78),
        Color(white: 0.72), Color(white: 0.78), Color(white: 0.78), Color(white: 0.72),
    ]
}

// MARK: - Bulle du score

/// Cercle portant le chiffre du score. Deux rendus selon le `style` :
///   - **sobre** : mesh gradient interne + ombre douce + score blanc.
///   - **gradient** : glass effect (la carte porte déjà le mesh) + score
///     blanc, sans ombre (la carte fait office d'arrière-plan coloré).
private struct CercleScore: View {
    let score: Int?
    let style: StyleCarteScore

    private static let taille: CGFloat = 56

    var body: some View {
        ZStack {
            if let score {
                contenu(score: score)
            } else {
                contenuIndisponible
            }
        }
        .frame(width: Self.taille, height: Self.taille)
    }

    @ViewBuilder
    private func contenu(score: Int) -> some View {
        switch style {
        case .sobre:
            TimelineView(.animation) { contexte in
                MeshScore.gradient(
                    pour: score,
                    phase: MeshScore.phase(date: contexte.date)
                )
                .clipShape(Circle())
                .shadow(
                    color: CouleurScore.couleur(pour: score).opacity(0.35),
                    radius: 6,
                    x: 0,
                    y: 3
                )
            }

            texteScore(score)
                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)

        case .gradient:
            Color.clear
                .frame(width: Self.taille, height: Self.taille)
                .glassEffect(in: Circle())

            texteScore(score)
                .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
        }
    }

    private func texteScore(_ score: Int) -> some View {
        Text("\(score)")
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
    }

    @ViewBuilder
    private var contenuIndisponible: some View {
        switch style {
        case .sobre:
            Circle().fill(Color.secondary.opacity(0.18))
            Text("—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
        case .gradient:
            Color.clear
                .frame(width: Self.taille, height: Self.taille)
                .glassEffect(in: Circle())
            Text("—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Mini-graphique 7 jours (Swift Charts)

/// Mini bar chart des 7 derniers scores, axes masqués. La dernière
/// barre (jour courant) est mise en avant : couleur du score en variante
/// sobre, blanc plein en variante gradient. Les autres barres sont en
/// gris atténué (sobre) ou blanc translucide (gradient — pour simuler
/// l'effet glass à l'échelle d'une barre de 5pt).
private struct HistoriqueBarChart: View {
    let historique: [Int?]
    let scoreActuel: Int?
    let style: StyleCarteScore

    var body: some View {
        Chart {
            ForEach(Array(historique.enumerated()), id: \.offset) { index, valeur in
                BarMark(
                    x: .value("Jour", index),
                    y: .value("Score", hauteur(valeur)),
                    width: .fixed(5)
                )
                .foregroundStyle(couleurBarre(index: index, valeur: valeur))
                .cornerRadius(1.5)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .frame(width: 64, height: 44)
    }

    /// Plancher visuel : un score très bas (1–2) doit rester perceptible.
    /// Les valeurs `nil` occupent toute la hauteur (style « fantôme »).
    private func hauteur(_ valeur: Int?) -> Int {
        guard let valeur else { return 100 }
        return max(3, min(100, valeur))
    }

    private func couleurBarre(index: Int, valeur: Int?) -> AnyShapeStyle {
        let estActuelle = index == historique.count - 1
        switch style {
        case .sobre:
            if valeur == nil {
                return AnyShapeStyle(Color.secondary.opacity(0.18))
            }
            if estActuelle, let scoreActuel {
                return AnyShapeStyle(CouleurScore.couleur(pour: scoreActuel))
            }
            return AnyShapeStyle(Color.secondary.opacity(0.5))
        case .gradient:
            if valeur == nil {
                return AnyShapeStyle(Color.white.opacity(0.15))
            }
            if estActuelle {
                return AnyShapeStyle(Color.white)
            }
            return AnyShapeStyle(Color.white.opacity(0.45))
        }
    }
}

// MARK: - Aperçus

/// Wrapper de preview avec slider pour balayer toute la plage 0–100 et
/// observer simultanément les deux variants sur la même donnée. Le 7ᵉ
/// point de l'historique reflète le score courant.
private struct ApercuAvecSlider: View {
    @State private var score: Double = 82

    var body: some View {
        let contenu = ContenuCarteScore(
            score: Int(score),
            date: Date(),
            historique: [65, 78, 71, 55, 88, 73, Int(score)]
        )
        VStack(spacing: 20) {
            Spacer()

            CarteScoreQuotidien(contenu: contenu, style: .sobre, onTap: {})
            CarteScoreQuotidien(contenu: contenu, style: .gradient, onTap: {})

            VStack(spacing: 4) {
                Slider(value: $score, in: 0...100, step: 1)
                HStack {
                    Text("0")
                    Spacer()
                    Text("\(Int(score)) / 100")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("100")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Slider de score") {
    ApercuAvecSlider()
}

#Preview("Slider de score — sombre") {
    ApercuAvecSlider()
        .preferredColorScheme(.dark)
}

#Preview("Score indisponible") {
    let contenu = ContenuCarteScore(
        score: nil,
        date: Date(),
        historique: [60, nil, 72, 58, nil, 65, nil]
    )
    VStack(spacing: 16) {
        Spacer()
        CarteScoreQuotidien(contenu: contenu, style: .sobre, onTap: {})
        CarteScoreQuotidien(contenu: contenu, style: .gradient, onTap: {})
        Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
