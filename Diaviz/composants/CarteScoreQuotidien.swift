//
//  CarteScoreQuotidien.swift
//  diaviz
//
//  Created by Alexandre on 06/05/2026.
//

import SwiftUI
import Charts

/// Carte « score quotidien » — résumé glycémique de la veille, style
/// Apple Santé : barre de titre avec icône + chevron, puis cercle
/// dégradé portant le chiffre, qualificatif court, et mini-graphique
/// en barres des 7 derniers jours.
struct CarteScoreQuotidien: View {

    /// Score sur 100. `nil` quand la couverture CGM est insuffisante —
    /// la carte affiche alors « Indisponible » et un cercle gris.
    let score: Int?

    /// Date du score affiché (le dernier élément d'`historique`).
    let date: Date

    /// 7 derniers scores, du plus ancien au plus récent. Les valeurs
    /// `nil` sont rendues en barres atténuées.
    let historique: [Int?]

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                ligneTitre
                ligneContenu
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color(.separator).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelleAccessibilite)
        .accessibilityHint("Ouvre les détails du score")
    }

    /// Barre de titre style Apple Santé : icône tintée + titre coloré
    /// du score, chevron à droite.
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
                .foregroundStyle(.tertiary)
        }
    }

    private var ligneContenu: some View {
        HStack(spacing: 14) {
            CercleScore(score: score)

            Text(libelleQualitatif)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            HistoriqueBarChart(historique: historique, scoreActuel: score)
                .accessibilityHidden(true)
        }
    }

    private var couleurTitre: Color {
        guard let score else { return .secondary }
        return CouleurScore.couleur(pour: score)
    }

    /// Libellé qualitatif court affiché à droite du cercle. 5 paliers
    /// alignés sur les seuils visuels du projet (≥70 vert, 50–69 orange,
    /// <50 rouge), avec un cran supplémentaire en haut et en bas.
    private var libelleQualitatif: String {
        guard let score else { return "Indisponible" }
        switch score {
        case 90...:    return "Très bonne"
        case 70..<90:  return "Bonne"
        case 50..<70:  return "Moyenne"
        case 30..<50:  return "Difficile"
        default:       return "Très difficile"
        }
    }

    private var libelleAccessibilite: String {
        if let score {
            return "Score d'hier : \(score) sur 100, journée \(libelleQualitatif.lowercased())"
        }
        return "Score d'hier indisponible"
    }
}

// MARK: - Couleur d'accent du score

/// Teinte continue alignée sur le mesh gradient du cercle : `hue` croît
/// linéairement de 0 (rouge, score 0) à 0.33 (vert, score 100). Le titre
/// de la carte, la dernière barre de l'historique et l'ombre du cercle
/// utilisent tous cette même teinte pour rester visuellement raccord.
private enum CouleurScore {
    /// Hue continue : 0 (rouge) → 0.33 (vert), interpolation linéaire.
    static func hue(pour score: Int) -> Double {
        let borne = Double(min(100, max(0, score)))
        return (borne / 100.0) * 0.33
    }

    /// Couleur pleine d'accent. Saturation/brightness calibrées pour
    /// rester lisibles en petit (titre 15pt, barre 5pt de large) tout
    /// en correspondant à l'impression visuelle dominante du mesh
    /// gradient du cercle.
    static func couleur(pour score: Int) -> Color {
        Color(hue: hue(pour: score), saturation: 0.85, brightness: 0.80)
    }
}

// MARK: - Cercle dégradé avec score

/// Cercle rempli d'un `MeshGradient` 4×4 dont la teinte est interpolée
/// en continu de rouge (score 0) à vert (score 100), avec micro-variations
/// de hue (±0.03) sur les 16 stops pour des nuances proches mais distinctes.
/// Points intérieurs jitterisés pour casser la grille et donner un rendu
/// organique. Le chiffre du score est au centre, ombre douce dans la
/// teinte dominante.
private struct CercleScore: View {
    let score: Int?

    private static let taille: CGFloat = 56

    /// Points du mesh 4×4. Les 4 coins sont fixés ; les 8 points de bord
    /// glissent légèrement le long de leur axe contraint ; les 4 points
    /// intérieurs sont librement jitterisés. Jitter constant (pas
    /// dépendant du score) pour ne pas rejouer la position à chaque
    /// re-render.
    private static let points: [SIMD2<Float>] = [
        // Ligne 0 — bord supérieur (y = 0)
        SIMD2(0.00, 0.00), SIMD2(0.31, 0.00), SIMD2(0.68, 0.00), SIMD2(1.00, 0.00),
        // Ligne 1 — intérieur haut
        SIMD2(0.00, 0.28), SIMD2(0.37, 0.30), SIMD2(0.64, 0.26), SIMD2(1.00, 0.34),
        // Ligne 2 — intérieur bas
        SIMD2(0.00, 0.68), SIMD2(0.29, 0.66), SIMD2(0.71, 0.72), SIMD2(1.00, 0.64),
        // Ligne 3 — bord inférieur (y = 1)
        SIMD2(0.00, 1.00), SIMD2(0.33, 1.00), SIMD2(0.67, 1.00), SIMD2(1.00, 1.00),
    ]

    var body: some View {
        ZStack {
            if let score {
                let teinte = CouleurScore.hue(pour: score)
                MeshGradient(
                    width: 4,
                    height: 4,
                    points: Self.points,
                    colors: meshColors(hue: teinte)
                )
                .clipShape(Circle())
                .shadow(
                    color: CouleurScore.couleur(pour: score).opacity(0.35),
                    radius: 6,
                    x: 0,
                    y: 3
                )

                Text("\(score)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                Text("—")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.taille, height: Self.taille)
    }

    /// 16 stops pour le mesh 4×4. Trois axes de variation, volontairement
    /// resserrés pour que les nuances restent très proches :
    ///   - **hue** : jitter ±0.015 autour de `h`.
    ///   - **saturation** : plage [0.78, 0.92].
    ///   - **brightness** : plage [0.74, 0.92], décroît subtilement
    ///     du haut vers le bas pour un léger effet de relief sphérique.
    ///
    /// Les offsets de hue sont distribués de façon pseudo-aléatoire
    /// (mais fixés en dur) pour éviter de répéter la même teinte sur
    /// des stops voisins.
    private func meshColors(hue h: Double) -> [Color] {
        let dh: [Double] = [
            -0.015,  0.010, -0.005,  0.012,
             0.008, -0.015,  0.015, -0.010,
            -0.012,  0.015, -0.008,  0.005,
             0.010, -0.005,  0.012, -0.015,
        ]
        let saturations: [Double] = [
            0.78, 0.82, 0.80, 0.82,
            0.84, 0.90, 0.86, 0.88,
            0.88, 0.86, 0.92, 0.88,
            0.90, 0.88, 0.90, 0.92,
        ]
        let brightnesses: [Double] = [
            0.92, 0.90, 0.91, 0.89,
            0.86, 0.84, 0.85, 0.84,
            0.80, 0.78, 0.79, 0.81,
            0.76, 0.74, 0.75, 0.77,
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
    /// Nécessaire car les jitters peuvent passer sous 0 quand `h ≈ 0`
    /// (score très bas → autour du rouge pur).
    private func hueWrap(_ h: Double) -> Double {
        let v = h.truncatingRemainder(dividingBy: 1.0)
        return v < 0 ? v + 1.0 : v
    }
}

// MARK: - Mini-graphique 7 jours (Swift Charts)

/// Mini bar chart des 7 derniers scores, axes masqués. La dernière
/// barre (jour courant) reprend la couleur du score actuel ; les
/// précédentes sont neutres. Les jours sans donnée sont rendus en
/// barre pleine très atténuée.
private struct HistoriqueBarChart: View {
    let historique: [Int?]
    /// Score d'aujourd'hui — sert uniquement à colorer la dernière
    /// barre. Si `nil`, la dernière barre reste neutre.
    let scoreActuel: Int?

    var body: some View {
        Chart {
            ForEach(Array(historique.enumerated()), id: \.offset) { index, valeur in
                BarMark(
                    x: .value("Jour", index),
                    y: .value("Score", hauteur(valeur)),
                    width: .fixed(5)
                )
                .foregroundStyle(couleur(index: index, valeur: valeur))
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

    private func couleur(index: Int, valeur: Int?) -> Color {
        if valeur == nil {
            return Color.secondary.opacity(0.18)
        }
        let estActuelle = index == historique.count - 1
        guard estActuelle, let scoreActuel else {
            return Color.secondary.opacity(0.5)
        }
        return CouleurScore.couleur(pour: scoreActuel)
    }
}

// MARK: - Aperçus

/// Wrapper de preview avec slider pour balayer toute la plage 0–100 et
/// observer le mesh gradient se déplacer du rouge au vert en continu.
/// Le 7ᵉ point de l'historique reflète le score courant (donc la dernière
/// barre change aussi de couleur).
private struct ApercuAvecSlider: View {
    @State private var score: Double = 82

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            CarteScoreQuotidien(
                score: Int(score),
                date: Date(),
                historique: [65, 78, 71, 55, 88, 73, Int(score)],
                onTap: {}
            )

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
    VStack {
        Spacer()
        CarteScoreQuotidien(
            score: nil,
            date: Date(),
            historique: [60, nil, 72, 58, nil, 65, nil],
            onTap: {}
        )
        .padding()
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
