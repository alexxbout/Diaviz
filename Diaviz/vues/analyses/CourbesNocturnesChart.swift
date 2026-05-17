//
//  CourbesNocturnesChart.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI
import Charts

/// Carte 2 — superpose toutes les courbes nocturnes individuelles, la
/// tendance moyenne et les points d'hypo détectés sur la fenêtre
/// 00h-06h.
///
/// La couleur de la tendance moyenne suit le verdict (vert si adaptée,
/// orange sinon) pour rappeler visuellement le diagnostic global de la
/// carte 1. Les nuits individuelles restent en gris très léger pour
/// donner une impression de « brouillard » dont la tendance émerge.
struct CourbesNocturnesChart: View {

    let analyse: AnalyseBasaleDetail

    /// Échelle Y fixe, alignée sur la spec : 40-250 mg/dL couvre toutes
    /// les nuits observables (de l'hypo sévère ~50 à l'hyper marquée
    /// ~220). Une échelle fixe d'un render à l'autre permet à l'œil de
    /// comparer la forme des courbes quand on change de période.
    private static let plageY: ClosedRange<Double> = 40...250

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titre
            graphique
            legende
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Titre de section

    private var titre: some View {
        Text("Courbes nocturnes")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Chart Swift Charts

    private var graphique: some View {
        Chart {
            zoneCible
            seuilHypo
            marquesNuits
            marquesTendance
            marquesHypos
        }
        .chartYScale(domain: Self.plageY)
        .chartXScale(domain: 0...6)
        .chartXAxis { axeX }
        .chartYAxis { axeY }
        .frame(height: 200)
        .accessibilityLabel("Graphique des courbes nocturnes")
        .accessibilityValue(libelleAccessibleGraphique)
    }

    // MARK: - Marks (extraits pour soulager le type-checker Swift Charts)

    @ChartContentBuilder
    private var zoneCible: some ChartContent {
        RectangleMark(
            xStart: .value("Début", 0.0),
            xEnd: .value("Fin", 6.0),
            yStart: .value("Bas cible", 70.0),
            yEnd: .value("Haut cible", 180.0)
        )
        .foregroundStyle(Color.green.opacity(0.05))
    }

    @ChartContentBuilder
    private var seuilHypo: some ChartContent {
        RuleMark(y: .value("Hypo", 70.0))
            .foregroundStyle(Color.red.opacity(0.2))
            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
    }

    @ChartContentBuilder
    private var marquesNuits: some ChartContent {
        ForEach(analyse.courbes) { nuit in
            ForEach(nuit.points) { point in
                LineMark(
                    x: .value("Heure", point.heure),
                    y: .value("Glycémie", point.valeur),
                    series: .value("Nuit", nuit.id.uuidString)
                )
                .foregroundStyle(Color.secondary.opacity(0.15))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private var marquesTendance: some ChartContent {
        ForEach(analyse.tendanceMoyenne) { point in
            LineMark(
                x: .value("Heure", point.heure),
                y: .value("Glycémie", point.valeur),
                series: .value("Nuit", "tendance")
            )
            .foregroundStyle(couleurTendance)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var marquesHypos: some ChartContent {
        ForEach(pointsHypo) { point in
            PointMark(
                x: .value("Heure", point.heure),
                y: .value("Glycémie", point.valeur)
            )
            .foregroundStyle(Color.red)
            .symbolSize(20)
        }
    }

    // MARK: - Axes

    @AxisContentBuilder
    private var axeX: some AxisContent {
        AxisMarks(values: Array(0...6).map { Double($0) }) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let heure = value.as(Double.self) {
                    Text("\(Int(heure))h").font(.caption2)
                }
            }
        }
    }

    @AxisContentBuilder
    private var axeY: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text("\(Int(v))").font(.caption2)
                }
            }
        }
    }

    // MARK: - Légende

    private var legende: some View {
        HStack(spacing: 16) {
            puceLegende(couleur: Color.secondary.opacity(0.4),
                        forme: .ligne,
                        texte: "Nuits individuelles")
            puceLegende(couleur: couleurTendance,
                        forme: .ligne,
                        texte: "Tendance moyenne")
            puceLegende(couleur: .red,
                        forme: .point,
                        texte: "Hypos")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }

    private enum FormeLegende { case ligne, point }

    private func puceLegende(couleur: Color, forme: FormeLegende, texte: String) -> some View {
        HStack(spacing: 4) {
            switch forme {
            case .ligne:
                Capsule()
                    .fill(couleur)
                    .frame(width: 12, height: 2)
            case .point:
                Circle()
                    .fill(couleur)
                    .frame(width: 6, height: 6)
            }
            Text(texte)
        }
    }

    // MARK: - Dérivés

    /// Tous les points sous 70 — agrégés depuis toutes les nuits, pas
    /// seulement la tendance. C'est le signal le plus important pour
    /// alerter sur un risque hypo nocturne.
    private var pointsHypo: [PointCourbeNuit] {
        analyse.courbes.flatMap { $0.pointsHypo }
    }

    /// Vert pour `.adaptee`, orange pour les autres — la couleur grise
    /// (`donneesInsuffisantes`) reste lisible sur le fond et signale
    /// que le verdict n'est pas tranché.
    private var couleurTendance: Color {
        switch analyse.verdict {
        case .adaptee:                return .green
        case .tropHaute, .tropBasse:  return .orange
        case .donneesInsuffisantes:   return .secondary
        }
    }

    /// Résumé textuel à destination de VoiceOver — le chart lui-même
    /// n'est pas explorable par audio, on synthétise les chiffres clés.
    private var libelleAccessibleGraphique: String {
        let hypos = pointsHypo.count
        return "\(analyse.courbes.count) nuits superposées. \(hypos) points sous le seuil hypo."
    }
}

// MARK: - Aperçus

#Preview("Courbes - Trop haute") {
    CourbesNocturnesChart(analyse: .mockTropHaute)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Courbes - Adaptée") {
    CourbesNocturnesChart(analyse: .mockAdaptee)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Courbes - Données insuffisantes") {
    CourbesNocturnesChart(analyse: .mockInsuffisant)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
