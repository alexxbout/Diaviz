//
//  PageChargeActivite.swift
//  diaviz
//

import Charts
import SwiftUI

/// Page de détail « Activité » — pushée depuis `CarteChargeActivite`.
/// Faits bruts des 14 derniers jours : séances et marche soutenue, en
/// minutes, empilées par jour. **Aucune interprétation** : le niveau de
/// charge active (relatif à la référence) vit dans Analyses → Charge et
/// glycémie.
struct PageChargeActivite: View {

    let jours: [JourChargeActive]
    let marcheIncluse: Bool

    private var quatorze: [JourChargeActive] { Array(jours.suffix(14)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnTeteAnalyse(
                    surtitre: "Sport",
                    titre: "Activité",
                    accroche: "Vos séances et votre marche soutenue des 14 derniers jours.",
                    ambiance: .chargeActivite
                )
                totaux
                graphique
                Label(
                    "Marche soutenue : au moins 10 minutes d'affilée à 100 pas/min ou plus, hors séance enregistrée. La comparaison à votre référence est dans Analyses, Charge et glycémie.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .pageAvecBandeau(titre: "Activité")
    }

    // MARK: - Totaux

    private var totaux: some View {
        let recents = Array(quatorze.suffix(7))
        let precedents = Array(quatorze.prefix(max(0, quatorze.count - 7)))
        return VStack(alignment: .leading, spacing: 12) {
            ligneTotal(titre: "7 derniers jours", jours: recents)
            Divider()
            ligneTotal(titre: "Il y a 8 à 14 jours", jours: precedents)
            if !marcheIncluse {
                Text("Marche non lue depuis Apple Santé (autorisation « Pas »).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private func ligneTotal(titre: String, jours: [JourChargeActive]) -> some View {
        let seances = jours.reduce(0) { $0 + $1.nombreSeances }
        let minutesSeances = jours.reduce(0) { $0 + $1.minutesSeances }
        let minutesMarche = jours.reduce(0) { $0 + $1.minutesMarche }
        return VStack(alignment: .leading, spacing: 4) {
            Text(titre)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label(
                    seances == 0 ? "Aucune séance" : "\(seances) séance\(seances > 1 ? "s" : "") · \(DureeActivite.texte(minutesSeances))",
                    systemImage: "figure.run"
                )
                .foregroundStyle(CarteChargeActivite.teinteSeances)
                if marcheIncluse {
                    Label(DureeActivite.texte(minutesMarche), systemImage: "figure.walk")
                        .foregroundStyle(CarteChargeActivite.teinteMarche)
                }
            }
            .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Graphique

    private var graphique: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                legendePastille(couleur: CarteChargeActivite.teinteSeances, texte: "Séances")
                if marcheIncluse {
                    legendePastille(couleur: CarteChargeActivite.teinteMarche, texte: "Marche soutenue")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Chart {
                ForEach(quatorze) { jour in
                    BarMark(
                        x: .value("Jour", jour.jour, unit: .day),
                        y: .value("Minutes", jour.minutesSeances)
                    )
                    .foregroundStyle(by: .value("Type", "Séances"))
                    if marcheIncluse {
                        BarMark(
                            x: .value("Jour", jour.jour, unit: .day),
                            y: .value("Minutes", jour.minutesMarche)
                        )
                        .foregroundStyle(by: .value("Type", "Marche soutenue"))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Séances": CarteChargeActivite.teinteSeances,
                "Marche soutenue": CarteChargeActivite.teinteMarche,
            ])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v)) min").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private func legendePastille(couleur: Color, texte: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(couleur).frame(width: 7, height: 7)
            Text(texte)
        }
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    NavigationStack {
        PageChargeActivite(jours: ContexteChargeActive.mock.jours, marcheIncluse: true)
    }
}

#Preview("Sombre, marche non lue") {
    NavigationStack {
        PageChargeActivite(jours: ContexteChargeActive.mock.jours, marcheIncluse: false)
    }
    .preferredColorScheme(.dark)
}
#endif
