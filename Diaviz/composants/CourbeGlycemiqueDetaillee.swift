//
//  CourbeGlycemiqueDetaillee.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Charts
import SwiftUI

/// Sous-vue dédiée au rendu Swift Charts de `GraphiqueGlycemique`
/// (état `.disponible`). Extraction motivée par le coût de
/// type-checking SwiftUI sur les marks empilés et la lisibilité du
/// composant parent — toute la logique de tracé (zones, lignes de
/// seuil, courbe, marqueurs, axes) est centralisée ici.
struct CourbeGlycemiqueDetaillee: View {

    let config: GraphiqueGlycemique.Configuration

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            entete
            chart
        }
    }

    private var entete: some View {
        Text(config.header)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        Chart {
            zoneCible
            zoneActivite
            ligneHypo
            ligneHyper
            courbe
            marqueursContent
        }
        .chartXScale(domain: config.domaineX)
        .chartYScale(domain: config.domaineY)
        .chartXAxis { axeXContent }
        .chartYAxis { axeYContent }
        .chartPlotStyle { plot in
            // Asymétrique : marge haute généreuse pour les annotations sur
            // deux lignes (« Fin\n235 » côté sport dépasse davantage au-dessus
            // du point qu'un simple « 246 » côté repas — 24pt suffisait pour
            // une ligne mais laissait le libellé déborder du cadre et chevaucher
            // le header au-dessus pour les labels à deux lignes). Marge basse
            // réduite pour ne pas laisser d'espace vide sous l'axe X.
            plot.padding(.top, 40).padding(.bottom, 6)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(config.header))
    }

    // MARK: - Zones de fond

    /// Bande verte transparente sur la cible 70-180 mg/dL.
    @ChartContentBuilder
    private var zoneCible: some ChartContent {
        RectangleMark(
            xStart: .value("Début", config.domaineX.lowerBound),
            xEnd: .value("Fin", config.domaineX.upperBound),
            yStart: .value("Cible bas", 70),
            yEnd: .value("Cible haut", 180)
        )
        .foregroundStyle(.green.opacity(0.08))
    }

    /// Bandeau bleu sur la fenêtre d'effort — sport uniquement.
    @ChartContentBuilder
    private var zoneActivite: some ChartContent {
        if let plage = config.zoneActivite {
            RectangleMark(
                xStart: .value("Début effort", plage.lowerBound),
                xEnd: .value("Fin effort", plage.upperBound),
                yStart: .value("Y bas", config.domaineY.lowerBound),
                yEnd: .value("Y haut", config.domaineY.upperBound)
            )
            .foregroundStyle(.blue.opacity(0.06))
        }
    }

    // MARK: - Lignes de seuil

    @ChartContentBuilder
    private var ligneHypo: some ChartContent {
        RuleMark(y: .value("Hypo", 70))
            .foregroundStyle(.red.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    @ChartContentBuilder
    private var ligneHyper: some ChartContent {
        RuleMark(y: .value("Hyper", 180))
            .foregroundStyle(.orange.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    // MARK: - Courbe principale

    @ChartContentBuilder
    private var courbe: some ChartContent {
        ForEach(pointsAffichables) { point in
            LineMark(
                x: .value("Temps", point.temps),
                y: .value("Glycémie", point.valeur)
            )
            .foregroundStyle(config.couleurCourbe)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
    }

    /// Points filtrés à la fenêtre affichée (avec une marge de 5min
    /// pour que l'interpolation reste fluide aux extrémités).
    private var pointsAffichables: [GraphiqueGlycemique.PointCourbe] {
        let marge: TimeInterval = 5 * 60
        let basse = config.domaineX.lowerBound - marge
        let haute = config.domaineX.upperBound + marge
        return config.pointsCourbe.filter { $0.temps >= basse && $0.temps <= haute }
    }

    // MARK: - Marqueurs

    @ChartContentBuilder
    private var marqueursContent: some ChartContent {
        ForEach(config.marqueurs) { marqueur in
            marqueurMark(marqueur)
        }
    }

    /// Construit un PointMark + son symbole + son annotation. Les
    /// trois cas (style ouvert / plein, label haut / bas / aucun)
    /// sont composés ici plutôt que d'éclater en sous-vues : le
    /// type `ChartContent` ne se compose pas aussi naturellement
    /// que `View`, donc on garde tout au même endroit.
    @ChartContentBuilder
    private func marqueurMark(
        _ m: GraphiqueGlycemique.Marqueur
    ) -> some ChartContent {
        switch m.style {
        case .cercleOuvert:
            PointMark(
                x: .value("Temps", m.temps),
                y: .value("Glycémie", m.valeur)
            )
            .symbol {
                Circle()
                    .strokeBorder(m.couleur, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            }
            .annotation(
                position: positionAnnotation(m.label),
                alignment: alignmentAnnotation(m.label),
                spacing: 4
            ) {
                texteAnnotation(m)
            }
        case .cerclePlein(let taille):
            PointMark(
                x: .value("Temps", m.temps),
                y: .value("Glycémie", m.valeur)
            )
            .symbol(.circle)
            .symbolSize(taille)
            .foregroundStyle(m.couleur)
            .annotation(
                position: positionAnnotation(m.label),
                alignment: alignmentAnnotation(m.label),
                spacing: 4
            ) {
                texteAnnotation(m)
            }
        }
    }

    @ViewBuilder
    private func texteAnnotation(_ m: GraphiqueGlycemique.Marqueur) -> some View {
        if let label = m.label {
            Text(label.texte)
                .font(.caption2.bold())
                .foregroundStyle(m.couleur)
                .multilineTextAlignment(.center)
                .monospacedDigit()
        }
    }

    private func positionAnnotation(
        _ label: GraphiqueGlycemique.Marqueur.Label?
    ) -> AnnotationPosition {
        switch label?.position {
        case .bas:    return .bottom
        case .haut:   return .top
        case .none:   return .top
        }
    }

    private func alignmentAnnotation(
        _ label: GraphiqueGlycemique.Marqueur.Label?
    ) -> Alignment {
        switch label?.alignement {
        case .leading:   return .leading
        case .trailing:  return .trailing
        case .none:      return .center
        default:         return .center
        }
    }

    // MARK: - Axes

    private var axeXContent: some AxisContent {
        AxisMarks(values: config.xMarques) { valeur in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let temps = valeur.as(TimeInterval.self) {
                    Text(config.formatLabelTemps(temps))
                        .font(.caption2)
                }
            }
        }
    }

    private var axeYContent: some AxisContent {
        AxisMarks(position: .trailing, values: config.yMarques) { valeur in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let v = valeur.as(Double.self) {
                    Text("\(Int(v))")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
        }
    }
}
