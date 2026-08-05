//
//  SheetEcartRatio.swift
//  diaviz
//

import SwiftUI

/// Sheet de détail de l'écart de ratio détecté par R1 — ouverte depuis la
/// carte d'insight « Nouvelles tendances » (tap sur l'insight R1
/// uniquement) et depuis `CarteAnalyseRatio` sur l'accueil. Un bloc par
/// groupe en écart (`section.ecart != nil`, filtré par l'appelant), chacun
/// avec son `GraphiqueZonesRatio` et la légende chiffrée des 3 tranches.
struct SheetEcartRatio: View {

    let sections: [ObservationRatioSection]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sections.isEmpty {
                    ContentUnavailableView(
                        "Aucun écart détecté",
                        systemImage: "chart.dots.scatter",
                        description: Text("Pas encore assez de repas dans une zone différente de ton ratio actuel pour comparer.")
                    )
                } else {
                    Form {
                        Section("Constat") {
                            Text("Chaque point est un repas, selon la dose donnée vs celle que suggère ton ratio (zone grisée). Bon = glycémie restée en cible, moyen et mauvais comptent ensemble, en rouge. Si un côté bat le milieu, ton ratio est mal calibré dans cette direction — trop fort à gauche, trop faible à droite.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(sections, id: \.groupe) { section in
                            Section(CalculRatioObserve.libelleGroupe(section.groupe)) {
                                GraphiqueZonesRatio(entrees: section.entrees)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                                legende(section)
                            }
                        }

                        Section {
                            Text("Basé sur les 45 derniers jours, au moins 30 repas exploitables par moment et 5 par zone. Un repas ajusté (sport, hypo…) ou à contexte libre n'est jamais compté.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Écart de ratio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func legende(_ section: ObservationRatioSection) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(TrancheRatio.allCases, id: \.self) { tranche in
                let bucket = section.buckets.first { $0.tranche == tranche }
                let gagnante = tranche == section.ecart?.trancheOptimale
                VStack(spacing: 4) {
                    Text(libelleCourt(tranche))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let bucket {
                        Text("\(bucket.bons)/\(bucket.total)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(gagnante ? Color.accentColor : .primary)
                    } else {
                        Text("insuffisant")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    // Ratio configuré affiché seulement sous « proche » —
                    // faible/élevée regroupent des repas à des doses
                    // *différentes* les unes des autres (c'est justement ce
                    // qui les distingue), une seule valeur moyennée y serait
                    // trompeuse. Le ratio configuré, lui, est identique pour
                    // toutes les entrées du groupe (`glucides / doseSuggeree`).
                    if tranche == .doseProche, let ratio = ratioConfigureAffiche(section) {
                        Text(ratio)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    // Signale explicitement quelle tranche tire le constat
                    // — sans ça, repérer si le mieux est à gauche ou à
                    // droite demande de comparer les 3 chiffres de tête.
                    if gagnante {
                        Text("meilleur taux")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func ratioConfigureAffiche(_ section: ObservationRatioSection) -> String? {
        guard let reference = section.entrees.first(where: { $0.doseSuggeree > 0 }) else { return nil }
        let ratio = Double(reference.glucides) / reference.doseSuggeree
        return "1u/\(Int(ratio.rounded()))g"
    }

    private func libelleCourt(_ tranche: TrancheRatio) -> String {
        switch tranche {
        case .doseNettementFaible: return "Dose plus faible"
        case .doseProche:          return "Ton ratio actuel"
        case .doseNettementForte:  return "Dose plus élevée"
        }
    }
}

// MARK: - Aperçus

private func _lot(groupe: SectionRepas?, bon: Int, total: Int, plage: ClosedRange<Double>) -> [EntreeRatioRepas] {
    // doseSuggeree: 10 pour glucides: 100 → ratio configuré affiché "1u/10g".
    // Les repas « pas bon » alternent moyen/mauvais, pour que le rouge
    // apparaisse aussi dans les previews, pas seulement l'orange.
    (0..<total).map { i in
        let ratio = plage.lowerBound + (plage.upperBound - plage.lowerBound) * Double(i) / Double(max(1, total - 1))
        let verdict: VerdictGlycemique = i < bon ? .bon : (i.isMultiple(of: 2) ? .moyen : .mauvais)
        return EntreeRatioRepas(
            id: UUID(), groupe: groupe, doseAppliquee: ratio * 10, doseSuggeree: 10,
            glucides: 100, verdict: verdict
        )
    }
}

private func _mockSections() -> [ObservationRatioSection] {
    let dejeuner = ObservationRatioSection(
        groupe: .dejeuner, effectif: 44,
        buckets: [
            BucketRatioObserve(tranche: .doseNettementFaible, total: 17, bons: 14),
            BucketRatioObserve(tranche: .doseProche, total: 20, bons: 11),
            BucketRatioObserve(tranche: .doseNettementForte, total: 7, bons: 3),
        ],
        ecart: EcartRatioObserve(bonsConfigure: 11, effectifConfigure: 20, trancheOptimale: .doseNettementFaible, bonsOptimal: 14, effectifOptimal: 17),
        entrees: _lot(groupe: .dejeuner, bon: 14, total: 17, plage: 0.55...0.78)
            + _lot(groupe: .dejeuner, bon: 11, total: 20, plage: 0.85...1.15)
            + _lot(groupe: .dejeuner, bon: 3, total: 7, plage: 1.22...1.55)
    )

    let diner = ObservationRatioSection(
        groupe: .diner, effectif: 38,
        buckets: [
            BucketRatioObserve(tranche: .doseProche, total: 25, bons: 12),
            BucketRatioObserve(tranche: .doseNettementForte, total: 13, bons: 10),
        ],
        ecart: EcartRatioObserve(bonsConfigure: 12, effectifConfigure: 25, trancheOptimale: .doseNettementForte, bonsOptimal: 10, effectifOptimal: 13),
        entrees: _lot(groupe: .diner, bon: 12, total: 25, plage: 0.85...1.15)
            + _lot(groupe: .diner, bon: 10, total: 13, plage: 1.25...1.5)
    )

    return [dejeuner, diner]
}

#Preview("2 groupes en écart") {
    SheetEcartRatio(sections: _mockSections())
}

#Preview("Aucun écart") {
    SheetEcartRatio(sections: [])
}
