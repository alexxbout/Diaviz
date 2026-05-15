//
//  CarteHypos.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import SwiftUI
import Charts

/// Carte "Hypoglycémies du jour" — première carte de la grille
/// d'accueil. Mise en page commune à toutes les cartes : **icône
/// + titre** dans une ligne en haut, valeur en gros au milieu, sous-
/// libellé optionnel, et **mini-courbe CGM 24h** en bas.
///
/// Deux états visuels distingués **uniquement par les accents
/// colorés** (icône, valeur, points sur la courbe) — pas de teinte
/// de fond :
///  - **0 hypo** : icône et valeur en vert (#1D9E75), pas de
///    sous-libellé, courbe CGM sans point rouge.
///  - **1+ hypos** : icône et valeur en rouge (#E24B4A), sous-
///    libellé détaillant la répartition sévère / légère, points
///    rouges sur la courbe aux passages sous 70 mg/dL.
///
/// La ligne de référence rouge pointillée à 70 reste visible dans
/// tous les cas — sert de repère même quand aucune hypo n'a eu lieu.
struct CarteHypos: View {

    let count: Int
    let severes: Int
    let legeres: Int

    /// 48 lectures CGM espacées de 30min sur la journée. La carte
    /// extrait elle-même les points hypos (< 70) pour les surligner.
    let pointsCgm: [LectureCgm]

    /// Points de glycémie passés sous le seuil hypo — calculé une fois
    /// par render pour ne pas re-filtrer à chaque BarMark.
    private var pointsHypo: [LectureCgm] {
        pointsCgm.filter { $0.valeur < 70 }
    }

    var body: some View {
        CarteMetriqueShell {
            // VStack à spacing 0 + paddings explicites — c'est ce qui
            // garantit que la valeur (et donc tous les chiffres de la
            // grille) soit à un Y identique sur les 4 cartes : le gap
            // titre→valeur est constant (24pt), le contenu sous la
            // valeur est poussé en bas par un Spacer absorbant.
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Ligne icône + titre (haut)
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.down.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(couleurAccent)
                        .accessibilityHidden(true)
                    Text("Hypos")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                // MARK: Valeur principale (Y fixe = 24pt sous le titre)
                Text("\(count)")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(couleurAccent)
                    .monospacedDigit()
                    .padding(.top, 24)

                // MARK: Sous-libellé contextuel — collé sous la valeur
                if count > 0 {
                    Text(sousLibelle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)
                }

                // MARK: Spacer absorbant — pousse la courbe au bas de
                // la carte sans bouger la valeur.
                Spacer(minLength: 0)

                // MARK: Mini-courbe CGM 24h (ancrée en bas)
                if !pointsCgm.isEmpty {
                    courbeCgm
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibilite)
    }

    /// Mini-courbe Swift Charts — 24pt de haut, sans axe ni légende.
    /// Trois couches : ligne CGM grise lissée, ligne de référence
    /// rouge pointillée à 70 mg/dL, points rouges sur les hypos.
    private var courbeCgm: some View {
        Chart {
            // Trace CGM — courbe continue lissée en catmullRom.
            ForEach(pointsCgm, id: \.heure) { point in
                LineMark(
                    x: .value("Heure", point.heure),
                    y: .value("Glycémie", point.valeur)
                )
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            // Seuil hypo — visible même à zéro hypo, sert de repère.
            RuleMark(y: .value("Hypo", 70))
                .foregroundStyle(Color.red.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [2, 2]))

            // Marqueurs des passages sous le seuil.
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
        .frame(height: 40)
    }

    // MARK: - Apparence dérivée du compte

    /// Vert "tout va bien" (#1D9E75) à zéro hypo, rouge "alerte"
    /// (#E24B4A) dès la première. Les deux teintes sont reprises de la
    /// charte de l'app pour rester raccord avec les visualisations
    /// glycémiques.
    private var couleurAccent: Color {
        count == 0
            ? Color(red: 0x1D / 255, green: 0x9E / 255, blue: 0x75 / 255)
            : Color(red: 0xE2 / 255, green: 0x4B / 255, blue: 0x4A / 255)
    }

    /// Détail répartition sévère / légère. N'est affiché qu'au-delà de
    /// zéro hypo — on évite "0 sévère · 0 légère" sous une valeur "0".
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
    .frame(width: 170, height: 180)
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
    .frame(width: 170, height: 180)
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Hypos - 3 légères") {
    CarteHypos(
        count: 3,
        severes: 0,
        legeres: 3,
        pointsCgm: MetriquesAccueil.mockAlerte.pointsCgmJournee
    )
    .frame(width: 170, height: 180)
    .padding()
    .background(Color(.systemGroupedBackground))
}
