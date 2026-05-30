//
//  RepartitionNuitsVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Carte 3 — répartition des **zones analysées** (zones 2 + 3 — seules
/// concernées par le calcul de pente basale).
///
/// V3 : pivot des nuits aux zones. Chaque zone exploitable est
/// classée dans une catégorie selon sa pente :
///   - stable (`|slope| ≤ 1`) → vert
///   - descendante (`slope < -1`) → ambre
///   - ascendante (`slope > 1`) → rouge
/// Les zones exclues sont comptées séparément. Les zones 1
/// (pré-endormissement) et 4 (dawn) ne participent jamais à la
/// répartition.
/// Périodes proposées par le picker en tête de la carte. 14 j est la
/// fenêtre clinique standard utilisée par le verdict de la page —
/// c'est aussi la valeur par défaut. 3 j zoome sur les toutes
/// dernières nuits, 7 j montre la semaine récente.
enum PeriodeRepartition: Int, CaseIterable, Identifiable, Sendable {
    case trois = 3
    case sept = 7
    case quatorze = 14
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .trois:     return "3 j"
        case .sept:      return "7 j"
        case .quatorze:  return "14 j"
        }
    }
    var labelLong: String {
        switch self {
        case .trois:     return "3 derniers jours"
        case .sept:      return "7 derniers jours"
        case .quatorze:  return "14 derniers jours"
        }
    }
}

struct RepartitionNuitsVue: View {

    let analyse: AnalyseBasaleDetail

    @State private var periode: PeriodeRepartition = .trois

    private var distribution: BasalDistribution {
        analyse.basalDistribution(daysBack: periode.rawValue)
    }

    init(analyse: AnalyseBasaleDetail) {
        self.analyse = analyse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                titre
                explainer
            }
            pickerPeriode
            VStack(alignment: .leading, spacing: 6) {
                libelleBarre
                barreSegmentee
            }
            listeMetriques
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Picker période

    /// Bascule la fenêtre d'analyse : 7 j (récent) / 14 j (clinique
    /// standard, default — cohérent avec le verdict de la page) / 30 j
    /// (lissé). Le changement recalcule `distribution` à la volée.
    private var pickerPeriode: some View {
        Picker("Période", selection: $periode) {
            ForEach(PeriodeRepartition.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Période d'analyse de la répartition")
    }

    // MARK: - Titre + explainer

    private var titre: some View {
        Text("Répartition")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// Explique quelles zones nourrissent l'analyse — sans ce repère,
    /// l'utilisateur peut penser que la barre est un TIR (alors que
    /// les phases pré-endormissement et dawn n'entrent pas dans le calcul).
    private var explainer: some View {
        Text("Calcul basé sur les zones d'endormissement et de nuit profonde — les phases pré-endormissement et dawn restent contextuelles.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Barre segmentée (3 segments — exclus pas dans la barre)

    private var nbZonesAnalysees: Int {
        distribution.stableZones + distribution.descendingZones + distribution.ascendingZones
    }

    /// Précise au-dessus de la barre sur quoi elle est calculée — la
    /// barre montre la part de chaque catégorie sur les zones
    /// effectivement analysées (zones exclues mises de côté), et sur
    /// quelle fenêtre temporelle (alignée sur le picker).
    private var libelleBarre: some View {
        Text("Sur \(nbZonesAnalysees) zones analysées · \(periode.labelLong)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var barreSegmentee: some View {
        BarreZones(
            stables: distribution.stableZones,
            descendantes: distribution.descendingZones,
            ascendantes: distribution.ascendingZones
        )
    }

    // MARK: - Liste métriques

    private var listeMetriques: some View {
        VStack(alignment: .leading, spacing: 10) {
            ligneMetrique(icone: "arrow.right", couleurIcone: .green,
                          label: "Zones stables",
                          valeur: "\(distribution.stableZones)")
            ligneMetrique(icone: "arrow.down.right", couleurIcone: .orange,
                          label: "Zones tendance basse",
                          valeur: "\(distribution.descendingZones)")
            ligneMetrique(icone: "arrow.up.right", couleurIcone: .red,
                          label: "Zones tendance haute",
                          valeur: "\(distribution.ascendingZones)")
            ligneMetrique(icone: "circle.dashed", couleurIcone: .secondary,
                          label: "Zones exclues",
                          valeur: "\(distribution.excludedZones)")

            Divider()

            ligneMetrique(icone: "exclamationmark.triangle.fill", couleurIcone: .red,
                          label: "Hypos nocturnes",
                          valeur: "\(distribution.hypoCount)")
            ligneMetrique(icone: "arrow.triangle.2.circlepath", couleurIcone: .green,
                          label: "Resucrages avec rechute",
                          valeur: "\(distribution.resucrageCount)")

            Divider()

            ligneMetrique(icone: "sunrise.fill", couleurIcone: .orange,
                          label: "Glycémie moy. réveil",
                          valeur: distribution.avgWakeUpGlucose > 0
                              ? "\(Int(distribution.avgWakeUpGlucose)) mg/dL"
                              : "—")
        }
        .padding(.top, 4)
    }

    /// Ligne métrique : SF Symbol coloré à gauche (taille uniforme),
    /// label centre, valeur à droite (`.medium`). Police 14 pt pour
    /// rester cohérente avec le reste du composant.
    private func ligneMetrique(
        icone: String,
        couleurIcone: Color,
        label: String,
        valeur: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(couleurIcone)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.primary)

            Spacer()

            Text(valeur)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(valeur)")
    }
}

// MARK: - Barre horizontale 3 segments

/// Reprend le langage de la barre AGP du score : 3 segments accolés,
/// hauteur 32 pt, coin arrondi 8 pt, pourcentage en blanc centré si ≥ 15 %.
///
/// **Différence avec V2** : on ne montre QUE les zones analysées
/// (stable / descendante / ascendante). Les zones exclues sortent du
/// dénominateur — elles sont comptées dans la liste sous la barre.
private struct BarreZones: View {

    let stables: Int
    let descendantes: Int
    let ascendantes: Int

    private static let hauteur: CGFloat = 32
    private static let coinArrondi: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = max(1, stables + descendantes + ascendantes)
            HStack(spacing: 0) {
                Segment(couleur: Color(red: 0.114, green: 0.620, blue: 0.459),
                        pourcent: pourcent(stables, sur: total))
                    .frame(width: largeur(stables, sur: total, total: geo.size.width))
                Segment(couleur: Color(red: 0.937, green: 0.624, blue: 0.153),
                        pourcent: pourcent(descendantes, sur: total))
                    .frame(width: largeur(descendantes, sur: total, total: geo.size.width))
                Segment(couleur: Color(red: 0.886, green: 0.294, blue: 0.290),
                        pourcent: pourcent(ascendantes, sur: total))
                    .frame(width: largeur(ascendantes, sur: total, total: geo.size.width))
            }
        }
        .frame(height: Self.hauteur)
        .clipShape(RoundedRectangle(cornerRadius: Self.coinArrondi, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(libelleAccessible)
    }

    private func pourcent(_ n: Int, sur total: Int) -> Double {
        100 * Double(n) / Double(total)
    }

    private func largeur(_ n: Int, sur total: Int, total largeurTotale: CGFloat) -> CGFloat {
        largeurTotale * CGFloat(n) / CGFloat(total)
    }

    private var libelleAccessible: String {
        let total = stables + descendantes + ascendantes
        return "Répartition sur \(total) zones analysées : \(stables) stables, \(descendantes) descendantes, \(ascendantes) ascendantes."
    }
}

private struct Segment: View {
    let couleur: Color
    let pourcent: Double

    var body: some View {
        ZStack {
            couleur
            if pourcent >= 15 {
                Text(String(format: "%.0f %%", pourcent))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Aperçus

#Preview("Répartition - Trop haute") {
    RepartitionNuitsVue(analyse: .mockTropHaute)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Répartition - Adaptée") {
    RepartitionNuitsVue(analyse: .mockAdaptee)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Répartition - No data") {
    RepartitionNuitsVue(analyse: .mockNoData)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
