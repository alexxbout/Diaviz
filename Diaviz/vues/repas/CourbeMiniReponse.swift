//
//  CourbeMiniReponse.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Charts
import SwiftUI

/// Sous-vue dédiée au rendu de la courbe Swift Charts pour
/// `MiniCourbeReponse`. L'extraction permet de garder le `body`
/// principal lisible et facilite le type-checking (les `Chart` à
/// plusieurs marks sont coûteux à inférer).
struct CourbeMiniReponse: View {

    let reponse: ReponseGlycemique

    var body: some View {
        Chart {
            // 1. La courbe glycémique. `ForEach` plutôt que
            //    `Chart(reponse.pointsCgm)` parce qu'on combine plusieurs
            //    types de marks dans le même graphe.
            ForEach(reponse.pointsCgm) { point in
                LineMark(
                    x: .value("Temps", point.secondesDepuisRepas),
                    y: .value("Glycémie", point.valeur)
                )
                .foregroundStyle(reponse.verdict.couleur)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            // 2. Marqueur T0 — petit cercle gris qui ancre l'instant du repas
            //    sur la courbe. Volontairement discret : ce n'est pas le focus.
            PointMark(
                x: .value("Temps", 0),
                y: .value("Glycémie", valeurT0)
            )
            .symbol(.circle)
            .symbolSize(15)
            .foregroundStyle(.secondary)

            // 3. Marqueur du pic — point plein, plus gros, dans la couleur du
            //    verdict, surmonté de la valeur numérique en mg/dL.
            PointMark(
                x: .value("Temps", reponse.tempsPic),
                y: .value("Glycémie", reponse.valeurPic)
            )
            .symbol(.circle)
            .symbolSize(50)
            .foregroundStyle(reponse.verdict.couleur)
            .annotation(position: .top, alignment: .center, spacing: 2) {
                Text("\(Int(reponse.valeurPic))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(reponse.verdict.couleur)
            }

            // 4. Marqueur du point le plus bas — affiché uniquement quand la
            //    courbe plonge sous la baseline pré-repas (cas hypo). Sinon
            //    c'est juste le retour normal en cible et ça surcharge la vue.
            if let pointMin = pointMinAAfficher {
                PointMark(
                    x: .value("Temps", pointMin.secondesDepuisRepas),
                    y: .value("Glycémie", pointMin.valeur)
                )
                .symbol(.circle)
                .symbolSize(50)
                .foregroundStyle(reponse.verdict.couleur)
                .annotation(position: .bottom, alignment: .center, spacing: 2) {
                    Text("\(Int(pointMin.valeur))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(reponse.verdict.couleur)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // Échelle X fixe : T-1h à T+4h. L'axe est caché mais l'échelle pilote
        // le placement horizontal des marks et garantit que toutes les
        // courbes ont la même largeur temporelle (comparables visuellement).
        .chartXScale(domain: -3600...14400)
        .chartYScale(domain: yAxisDomain)
        // 12pt en haut ET en bas pour laisser place aux annotations textuelles
        // (valeur du pic en haut, valeur du minimum en bas — quand affiché).
        // Padding constant pour éviter que la zone du tracé saute en hauteur
        // d'une row à l'autre selon que le min est annoté ou pas.
        .chartPlotStyle { plot in
            plot.padding(.vertical, 12)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(reponse.verdict.descriptionAccessibilite))
        .accessibilityValue(Text(descriptionVoiceOver))
    }

    /// Glycémie à T=0 (instant exact du repas). La fenêtre étant échantillonnée
    /// par pas de 5min à partir de -3600s, un point tombe pile sur 0 — on le
    /// récupère directement, avec un fallback sur le point le plus proche.
    private var valeurT0: Double {
        if let pile = reponse.pointsCgm.first(where: { $0.secondesDepuisRepas == 0 }) {
            return pile.valeur
        }
        return reponse.pointsCgm
            .min(by: { abs($0.secondesDepuisRepas) < abs($1.secondesDepuisRepas) })?
            .valeur ?? 110
    }

    /// Point le plus bas de la courbe post-repas, **à condition** qu'il
    /// plonge significativement sous la baseline T0 (≥ 15 mg/dL en dessous).
    /// Sinon, le min est juste le retour en cible — pas la peine de l'annoter.
    /// Seuil 15 mg/dL : empirique, suffisant pour distinguer un vrai creux
    /// (hypo, sortie de cible par le bas) d'un simple retour stable.
    private var pointMinAAfficher: PointCgm? {
        let postRepas = reponse.pointsCgm.filter { $0.secondesDepuisRepas >= 0 }
        guard let min = postRepas.min(by: { $0.valeur < $1.valeur }) else { return nil }
        guard min.valeur < valeurT0 - 15 else { return nil }
        return min
    }

    /// Domaine Y dynamique : bornes basées sur les valeurs effectives de la
    /// courbe (avec un peu d'air en haut/bas). Le marqueur du pic — et
    /// éventuellement du minimum — sera ainsi toujours dans la zone de tracé.
    private var yAxisDomain: ClosedRange<Double> {
        let valeurs = reponse.pointsCgm.map(\.valeur)
        let mini = (valeurs.min() ?? 70) - 5
        let maxi = (valeurs.max() ?? 200) + 5
        return mini...maxi
    }

    /// Texte VoiceOver mentionnant le pic et, le cas échéant, le minimum.
    private var descriptionVoiceOver: String {
        var parts: [String] = ["Pic à \(Int(reponse.valeurPic)) milligrammes par décilitre"]
        if let min = pointMinAAfficher {
            parts.append("minimum à \(Int(min.valeur))")
        }
        return parts.joined(separator: ", ")
    }
}
