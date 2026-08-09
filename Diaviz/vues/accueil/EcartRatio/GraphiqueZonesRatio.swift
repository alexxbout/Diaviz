//
//  GraphiqueZonesRatio.swift
//  diaviz
//

import Charts
import SwiftUI

/// Graphique de dispersion — un point par repas exploitable d'un groupe,
/// positionné selon son ratio `doseAppliquee / doseSuggeree`, coloré selon
/// `VerdictGlycemique.couleur`  (vert `.bon`, orange `.moyen`, rouge
/// `.mauvais` — même palette que le reste de l'app, ex. `GraphiqueGlycemique`).
/// Le mining lui-même (`CalculRatioObserve.construireSection`) ne distingue
/// que « bon » vs « pas bon » pour le taux affiché en légende, mais rien
/// n'empêche le graphique de montrer la nuance complète.
///
/// Zone « proche du ratio » teintée en fond (coins arrondis), séparateurs
/// aux bornes de tolérance, ligne pointillée au ratio configuré (x=1.0).
/// Axes masqués — les libellés de zone (tranche + taux) vivent dans la
/// légende sous le graphique, portée par l'appelant (`SheetEcartRatio`).
struct GraphiqueZonesRatio: View {

    let entrees: [EntreeRatioRepas]

    private var points: [(id: UUID, ratio: Double, jitter: Double, couleur: Color)] {
        entrees.compactMap { entree in
            guard entree.doseSuggeree > 0 else { return nil }
            let ratio = entree.doseAppliquee / entree.doseSuggeree
            return (entree.id, ratio, jitter(entree.id), entree.verdict.couleur)
        }
    }

    private var borneFaible: Double { 1 - CalculRatioObserve.toleranceRatio }
    private var borneForte: Double { 1 + CalculRatioObserve.toleranceRatio }

    /// Domaine data-driven : englobe toujours la zone « proche », s'étend
    /// aux valeurs réelles si elles dépassent — même logique que
    /// `GraphiqueGlycemique.Configuration.echelleY` (coller aux données).
    private var domaine: ClosedRange<Double> {
        let valeurs = points.map(\.ratio)
        let bas = min(valeurs.min() ?? borneFaible, borneFaible) - 0.05
        let haut = max(valeurs.max() ?? borneForte, borneForte) + 0.05
        return bas...haut
    }

    var body: some View {
        Chart {
            RuleMark(x: .value("Borne faible", borneFaible))
                .foregroundStyle(Color(.separator))
                .lineStyle(StrokeStyle(lineWidth: 0.5))

            RuleMark(x: .value("Borne forte", borneForte))
                .foregroundStyle(Color(.separator))
                .lineStyle(StrokeStyle(lineWidth: 0.5))

            RuleMark(x: .value("Ratio configuré", 1.0))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

            ForEach(points, id: \.id) { point in
                PointMark(
                    x: .value("Ratio", point.ratio),
                    y: .value("", point.jitter)
                )
                .foregroundStyle(point.couleur)
                .symbolSize(26)
                .opacity(0.85)
            }
        }
        .chartXScale(domain: domaine)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // Zone « proche du ratio » dessinée en fond plutôt qu'en `RectangleMark`
        // — `RectangleMark` n'a pas de coin arrondi natif, alors qu'un
        // `RoundedRectangle` positionné via `proxy.position(forX:)` sur les
        // coordonnées du plot area en a un directement.
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame,
                   let xDebut = proxy.position(forX: borneFaible),
                   let xFin = proxy.position(forX: borneForte) {
                    let cadre = geo[plotFrame]
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: xFin - xDebut, height: cadre.height)
                        .position(x: cadre.minX + (xDebut + xFin) / 2, y: cadre.midY)
                }
            }
        }
        .frame(height: 64)
        .accessibilityHidden(true)
    }

    /// Position verticale déterministe dérivée de l'id — stable d'un rendu
    /// à l'autre (un `Double.random` ferait "sauter" les points visuellement
    /// à chaque recalcul de la vue).
    private func jitter(_ id: UUID) -> Double {
        Double(abs(id.hashValue % 1000)) / 1000.0 * 0.86 + 0.07
    }
}

// MARK: - Aperçus

private func _mockEntrees(faible: (bon: Int, total: Int), proche: (bon: Int, total: Int), forte: (bon: Int, total: Int)) -> [EntreeRatioRepas] {
    func lot(_ compte: (bon: Int, total: Int), plage: ClosedRange<Double>) -> [EntreeRatioRepas] {
        (0..<compte.total).map { i in
            let ratio = plage.lowerBound + (plage.upperBound - plage.lowerBound) * Double(i) / Double(max(1, compte.total - 1))
            // Les repas « pas bon » alternent moyen/mauvais — pour que le
            // rouge (mauvais) apparaisse aussi dans les previews, pas
            // seulement l'orange.
            let verdict: VerdictGlycemique = i < compte.bon ? .bon : (i.isMultiple(of: 2) ? .moyen : .mauvais)
            return EntreeRatioRepas(
                id: UUID(), groupe: nil, doseAppliquee: ratio * 10, doseSuggeree: 10,
                glucides: 40, verdict: verdict
            )
        }
    }
    return lot(faible, plage: 0.55...0.78) + lot(proche, plage: 0.85...1.15) + lot(forte, plage: 1.22...1.55)
}

#if DEBUG
#Preview("3 zones peuplées") {
    GraphiqueZonesRatio(entrees: _mockEntrees(faible: (14, 17), proche: (11, 20), forte: (3, 7)))
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
}

#Preview("2 zones (une sous le seuil)") {
    GraphiqueZonesRatio(entrees: _mockEntrees(faible: (0, 0), proche: (6, 13), forte: (5, 7)))
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
}

#Preview("Sombre") {
    GraphiqueZonesRatio(entrees: _mockEntrees(faible: (14, 17), proche: (11, 20), forte: (3, 7)))
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .preferredColorScheme(.dark)
}
#endif
