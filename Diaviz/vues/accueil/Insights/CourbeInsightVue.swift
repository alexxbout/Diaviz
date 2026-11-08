//
//  CourbeInsightVue.swift
//  diaviz
//

import SwiftUI
import Charts

/// Courbe d'une carte « réponse glycémique ». Même peau que les autres
/// graphiques glycémiques (`StyleGrapheGlycemie`) : lignes d'hypo et d'hyper
/// du profil, pas de bande de cible, pas d'axes, pas de texte sous la courbe.
/// Seul le repère (repas ou séance) est marqué.
struct CourbeInsightVue: View {

    let courbe: CourbeInsight
    let couleur: Color

    private static let hauteur: CGFloat = 96

    private var domaineY: ClosedRange<Double> {
        let valeurs = courbe.points.map(\.valeur)
        let bas = min(valeurs.min() ?? courbe.seuils.hypoglycemie, courbe.seuils.hypoglycemie) - 10
        let haut = max(valeurs.max() ?? courbe.seuils.hyperglycemie, courbe.seuils.hyperglycemie) + 10
        return bas...haut
    }

    private var domaineX: ClosedRange<Double> {
        let minutes = courbe.points.map(\.minutes)
        guard let premier = minutes.min(), let dernier = minutes.max(), premier < dernier else {
            return courbe.repere
        }
        return premier...dernier
    }

    /// Hypo en rouge, hyper en orange, comme les lignes de seuil ; le reste
    /// garde la couleur de la carte.
    private func teinte(_ zone: CourbeInsight.Zone) -> Color {
        switch zone {
        case .basse: StyleGrapheGlycemie.couleurSeuilBas
        case .haute: StyleGrapheGlycemie.couleurSeuilHaut
        case .cible: couleur
        }
    }

    var body: some View {
        Chart {
            if courbe.repereEstUneBande {
                RectangleMark(
                    xStart: .value("Début", courbe.repere.lowerBound),
                    xEnd: .value("Fin", courbe.repere.upperBound)
                )
                .foregroundStyle(Color.secondary.opacity(0.18))
            } else {
                RuleMark(x: .value("Repas", courbe.repere.lowerBound))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            StyleGrapheGlycemie.lignesSeuils(courbe.seuils)

            ForEach(Array(courbe.segments.enumerated()), id: \.offset) { indice, segment in
                ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Minutes", point.minutes),
                        y: .value("Glycémie", point.valeur),
                        series: .value("Segment", indice)
                    )
                    .foregroundStyle(teinte(segment.zone))
                    .lineStyle(StrokeStyle(
                        lineWidth: StyleGrapheGlycemie.epaisseurCourbe, lineCap: .round, lineJoin: .round
                    ))
                }
            }
        }
        .chartXScale(domain: domaineX)
        .chartYScale(domain: domaineY)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: Self.hauteur)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Courbe de glycémie")
        .accessibilityValue(courbe.pic.map { "Pic à \(Int($0.valeur.rounded())) milligrammes par décilitre" } ?? "")
    }
}

#if DEBUG
#Preview("Courbe repas") {
    let points = stride(from: -60, through: 240, by: 5).map { minutes -> CourbeInsight.Point in
        let t = Double(minutes)
        return .init(minutes: t, valeur: t < 0 ? 105 : 105 + 95 * (t / 75) * exp(1 - t / 75))
    }
    return CarteInsight(insight: Insight(
        id: UUID(), categorie: .reponse, titre: "Repas de 14:05", message: "",
        microVisuel: .courbe(CourbeInsight(
            points: points, repere: 0...0, repereEstUneBande: false,
            pic: points.max { $0.valeur < $1.valeur }, seuils: SeuilsGlycemiques()
        )),
        lienAnalyse: nil, libelleLien: "Voir la réponse →", destination: .importSport, teinte: .indigo
    ))
    .padding()
    .frame(height: 180)
    .background(Color(.systemGroupedBackground))
}
#endif
