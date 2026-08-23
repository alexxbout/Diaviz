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

    /// Un point par repas, positionné sur son **ratio effectif en g/u**
    /// (`glucides ÷ dose donnée`) — la même unité que les réglages, plutôt
    /// qu'un rapport de doses sans signification lisible.
    ///
    /// L'axe est ensuite **inversé** (voir `domaine`) pour que « moins
    /// d'insuline » reste à gauche : le ratio en g/u variant à l'inverse de
    /// l'insuline, un axe croissant mettrait le moins d'insuline à droite et
    /// invaliderait toutes les formulations de la sheet.
    private var points: [(id: UUID, ratio: Double, jitter: Double, couleur: Color)] {
        entrees.compactMap { entree in
            guard entree.doseAppliquee > 0, entree.glucides > 0 else { return nil }
            let ratioEffectif = Double(entree.glucides) / entree.doseAppliquee
            // Un `.mauvais` se colore selon sa cause quand elle est connue :
            // hypo et pic élevé sont deux échecs opposés. Les repas annotés
            // avant l'ajout du champ retombent sur le rouge d'origine.
            let couleur = entree.raisonMauvais?.couleur ?? entree.verdict.couleur
            return (entree.id, ratioEffectif, jitter(entree.id), couleur)
        }
    }

    /// Ratio configuré du groupe, reconstitué en g/u depuis n'importe quelle
    /// entrée (`glucides ÷ dose suggérée`) — identique pour tout le groupe,
    /// le filtrage par date de changement le garantit en amont.
    private var ratioConfigure: Double? {
        guard let reference = entrees.first(where: { $0.doseSuggeree > 0 && $0.glucides > 0 }) else { return nil }
        return Double(reference.glucides) / reference.doseSuggeree
    }

    /// Bornes de la zone « à ton ratio », en g/u. `borneMoinsInsuline` porte
    /// **plus** de grammes par unité — d'où le nom, qui suit l'insuline et
    /// non le chiffre.
    private var borneMoinsInsuline: Double? {
        ratioConfigure.map { $0 + CalculRatioObserve.toleranceGrammesParUnite }
    }
    private var borneePlusInsuline: Double? {
        ratioConfigure.map { $0 - CalculRatioObserve.toleranceGrammesParUnite }
    }

    /// Domaine data-driven, exprimé en g/u et **renvoyé décroissant** : la
    /// borne haute (beaucoup de grammes par unité = peu d'insuline) est à
    /// gauche. Englobe toujours la zone de tolérance, s'étend aux valeurs
    /// réelles si elles dépassent.
    private var domaine: [Double] {
        let valeurs = points.map(\.ratio)
        let reference = ratioConfigure ?? valeurs.first ?? 10
        let hautDefaut = borneMoinsInsuline ?? reference
        let basDefaut = borneePlusInsuline ?? reference
        let haut = max(valeurs.max() ?? hautDefaut, hautDefaut) + 0.5
        let bas = min(valeurs.min() ?? basDefaut, basDefaut) - 0.5
        return [haut, bas]
    }

    var body: some View {
        VStack(spacing: 6) {
            graphique

            // Sens de lecture rappelé sous chaque graphique : la sheet en
            // empile plusieurs, obliger à remonter jusqu'à une légende
            // commune ne marche pas à l'usage.
            HStack {
                Text("← moins d'insuline")
                Spacer()
                Text("plus d'insuline →")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var graphique: some View {
        Chart {
            if let borneMoinsInsuline, let borneePlusInsuline {
                RuleMark(x: .value("Borne moins d'insuline", borneMoinsInsuline))
                    .foregroundStyle(Color(.separator))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))

                RuleMark(x: .value("Borne plus d'insuline", borneePlusInsuline))
                    .foregroundStyle(Color(.separator))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
            }

            if let ratioConfigure {
                RuleMark(x: .value("Ratio configuré", ratioConfigure))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            ForEach(points, id: \.id) { point in
                PointMark(
                    x: .value("Ratio effectif", point.ratio),
                    y: .value("", point.jitter)
                )
                .foregroundStyle(point.couleur)
                .symbolSize(26)
                .opacity(0.85)
            }
        }
        .chartXScale(domain: domaine)
        .chartYScale(domain: 0...1)
        // Axe X visible désormais : il porte de vraies valeurs de ratio
        // (« 11g », « 12g »…), directement comparables aux réglages.
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { valeur in
                AxisGridLine().foregroundStyle(Color.clear)
                AxisValueLabel {
                    if let grammes = valeur.as(Double.self) {
                        Text("\(Int(grammes.rounded()))g")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // Zone « proche du ratio » dessinée en fond plutôt qu'en `RectangleMark`
        // — `RectangleMark` n'a pas de coin arrondi natif, alors qu'un
        // `RoundedRectangle` positionné via `proxy.position(forX:)` sur les
        // coordonnées du plot area en a un directement.
        .chartBackground { proxy in
            GeometryReader { geo in
                // `abs` sur la largeur : l'axe étant inversé, la borne
                // « moins d'insuline » se projette à gauche de l'autre.
                if let plotFrame = proxy.plotFrame,
                   let borneMoinsInsuline, let borneePlusInsuline,
                   let xDebut = proxy.position(forX: borneMoinsInsuline),
                   let xFin = proxy.position(forX: borneePlusInsuline) {
                    let cadre = geo[plotFrame]
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: abs(xFin - xDebut), height: cadre.height)
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

/// Repas de démo pour un ratio configuré de `1u/12g`, générés directement à
/// partir d'un **ratio effectif cible en g/u** — la dose est déduite, dans le
/// même sens que le vrai calcul (`dose = glucides ÷ ratio effectif`).
private func _mockEntrees(faible: (bon: Int, total: Int), proche: (bon: Int, total: Int), forte: (bon: Int, total: Int)) -> [EntreeRatioRepas] {
    let glucides = 60
    let ratioConfigure = 12.0

    func lot(_ compte: (bon: Int, total: Int), plage: ClosedRange<Double>) -> [EntreeRatioRepas] {
        (0..<compte.total).map { i in
            let ratioEffectif = plage.lowerBound
                + (plage.upperBound - plage.lowerBound) * Double(i) / Double(max(1, compte.total - 1))
            // Les repas « pas bon » alternent moyen/mauvais — pour que le
            // rouge (mauvais) apparaisse aussi dans les previews, pas
            // seulement l'orange.
            let verdict: VerdictGlycemique = i < compte.bon ? .bon : (i.isMultiple(of: 2) ? .moyen : .mauvais)
            return EntreeRatioRepas(
                id: UUID(), groupe: nil,
                doseAppliquee: Double(glucides) / ratioEffectif,
                doseSuggeree: Double(glucides) / ratioConfigure,
                glucides: glucides, verdict: verdict
            )
        }
    }

    // Moins d'insuline = plus de grammes par unité, donc au-dessus de 13.
    return lot(faible, plage: 13.2...16.0)
        + lot(proche, plage: 11.2...12.8)
        + lot(forte, plage: 9.0...10.8)
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
