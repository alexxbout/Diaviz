//
//  CarteHypos.swift
//  diaviz
//

import SwiftUI
import Charts

/// Row "Hypoglycémies du jour" de la liste d'accueil — la seule des 4
/// métriques à afficher un graphique : elle garde son en-tête compact
/// (icône + compteur) mais déplie un mini-graphe glycémique pleine largeur
/// en dessous, avec les passages sous le seuil hypo repérés en rouge.
///
/// Couleurs distinguées **uniquement par les accents** (icône, valeur,
/// points sur la courbe) :
///  - **0 hypo** : vert, pas de sous-libellé, courbe sans point rouge.
///  - **1+ hypos** : rouge, sous-libellé détaillant sévère / légère, points
///    rouges sur la courbe aux passages sous 70 mg/dL.
struct CarteHypos: View {

    let count: Int
    let severes: Int
    let legeres: Int

    /// 48 lectures CGM espacées de 30min sur la journée. La row extrait
    /// elle-même les points hypos (< 70) pour les surligner.
    let pointsCgm: [LectureCgm]

    private var pointsHypo: [LectureCgm] {
        pointsCgm.filter { $0.valeur < 70 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LigneMetriqueAccueil(
                icone: "arrowshape.down.circle.fill",
                couleurIcone: couleurAccent,
                couleurFondIcone: couleurAccent.opacity(0.15),
                titre: "Hypos",
                sousTitre: count > 0 ? sousLibelle : "Aucune aujourd'hui"
            ) {
                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(couleurAccent)
            }
            .padding(.bottom, 0)

            if !pointsCgm.isEmpty {
                courbeCgm
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibilite)
    }

    /// Mini-courbe Swift Charts pleine largeur — ligne CGM lissée, seuil
    /// hypo pointillé, points rouges sur les passages sous 70 mg/dL.
    private var courbeCgm: some View {
        Chart {
            ForEach(pointsCgm, id: \.heure) { point in
                LineMark(
                    x: .value("Heure", point.heure),
                    y: .value("Glycémie", point.valeur)
                )
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            RuleMark(y: .value("Hypo", 70))
                .foregroundStyle(Color.red.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [2, 2]))

            ForEach(pointsHypo, id: \.heure) { point in
                PointMark(
                    x: .value("Heure", point.heure),
                    y: .value("Glycémie", point.valeur)
                )
                .foregroundStyle(.red)
                .symbolSize(28)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 44)
    }

    // MARK: - Apparence dérivée du compte

    private var couleurAccent: Color {
        count == 0
            ? CouleurScore.couleur(pour: 100)
            : Color(red: 0xE2 / 255, green: 0x4B / 255, blue: 0x4A / 255)
    }

    private var sousLibelle: String {
        let parts: [String] = [
            severes > 0 ? "\(severes) sévère\(severes > 1 ? "s" : "")" : nil,
            legeres > 0 ? "\(legeres) légère\(legeres > 1 ? "s" : "")" : nil,
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private var libelleAccessibilite: String {
        if count == 0 {
            return "Aucune hypoglycémie aujourd'hui"
        }
        return "\(count) hypoglycémie\(count > 1 ? "s" : "") aujourd'hui : \(sousLibelle)"
    }
}

// MARK: - Aperçus

#Preview("Hypos - 0 avec courbe") {
    CarteHypos(
        count: 0,
        severes: 0,
        legeres: 0,
        pointsCgm: MetriquesAccueil.mockNormal.pointsCgmJournee
    )
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Hypos - 2 avec courbe") {
    CarteHypos(
        count: 2,
        severes: 1,
        legeres: 1,
        pointsCgm: MetriquesAccueil.mockAlerte.pointsCgmJournee
    )
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .padding()
    .background(Color(.systemGroupedBackground))
}
