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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MeshScore.gradient(pour: contenu.score))
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

    /// Mesh 3×3 (9 points) — chaque point couvre une zone plus large
    /// qu'en 4×4, donc les transitions sont intrinsèquement plus
    /// douces et le hue jitter ne crée plus de sauts visibles entre
    /// stops adjacents. Centre légèrement décalé (0.55, 0.45) pour un
    /// halo asymétrique plutôt que parfaitement centré, et bords
    /// microscopiquement off-grid pour un rendu organique.
    static let points: [SIMD2<Float>] = [
        // Ligne 0 — bord supérieur (y = 0)
        SIMD2(0.00, 0.00), SIMD2(0.48, 0.00), SIMD2(1.00, 0.00),
        // Ligne 1 — milieu (centre décalé en haut-droite)
        SIMD2(0.00, 0.52), SIMD2(0.55, 0.45), SIMD2(1.00, 0.48),
        // Ligne 2 — bord inférieur (y = 1)
        SIMD2(0.00, 1.00), SIMD2(0.52, 1.00), SIMD2(1.00, 1.00),
    ]

    static func gradient(pour score: Int?) -> MeshGradient {
        guard let score else {
            return MeshGradient(
                width: 3,
                height: 3,
                points: points,
                colors: nuancesGrises,
                colorSpace: .perceptual
            )
        }
        let teinte = CouleurScore.hue(pour: score)
        return MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: colors(hue: teinte),
            colorSpace: .perceptual
        )
    }

    /// 9 stops organisés pour faire émerger **deux courants chromatiques
    /// qui se croisent au centre** :
    ///
    ///   - **Diagonale principale (TL ↔ BR)** : teintes chaudes
    ///     (`dh > 0`) — l'œil suit une "vague" chaude qui traverse
    ///     d'angle haut-gauche à angle bas-droite.
    ///   - **Anti-diagonale (TR ↔ BL)** : teintes froides (`dh < 0`)
    ///     qui croisent la diagonale chaude au centre.
    ///   - **Centre** : highlight pastel (saturation 0.78, brightness
    ///     0.95) légèrement décalé en position pour casser la symétrie.
    ///
    /// Hue jitter modéré (±0.022) : assez visible pour que les courants
    /// chaud/froid soient perceptibles, mais sans sauts entre voisins.
    private static func colors(hue h: Double) -> [Color] {
        // Damier chaud/froid en croix :
        //   - Coins TL, BR (indices 0, 8) → chaud
        //   - Coins TR, BL (indices 2, 6) → froid
        //   - Bords correspondants suivent leur coin adjacent
        let dh: [Double] = [
            +0.022, -0.012, -0.022,   // TL chaud, top froid, TR froid
            +0.012,  0.000, -0.014,   // left chaud, centre neutre, right froid
            -0.020, +0.014, +0.024,   // BL froid, bottom chaud, BR chaud
        ]
        // Saturation : coins très saturés (couleurs profondes), bords
        // mid, centre pastel (pour le highlight).
        let saturations: [Double] = [
            0.92, 0.85, 0.94,
            0.85, 0.78, 0.88,
            0.94, 0.85, 0.92,
        ]
        // Brightness : centre max (highlight asymétrique), corners min,
        // edges intermédiaires.
        let brightnesses: [Double] = [
            0.68, 0.84, 0.66,
            0.85, 0.95, 0.84,
            0.66, 0.85, 0.68,
        ]
        return (0..<9).map { i in
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
    /// que `colors(hue:)` : highlight central, coins sombres, bords
    /// intermédiaires. 9 stops pour le mesh 3×3.
    private static let nuancesGrises: [Color] = [
        Color(white: 0.55), Color(white: 0.78), Color(white: 0.55),
        Color(white: 0.78), Color(white: 0.94), Color(white: 0.78),
        Color(white: 0.55), Color(white: 0.78), Color(white: 0.55),
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
            MeshScore.gradient(pour: score)
                .clipShape(Circle())
                .shadow(
                    color: CouleurScore.couleur(pour: score).opacity(0.35),
                    radius: 6,
                    x: 0,
                    y: 3
                )

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
