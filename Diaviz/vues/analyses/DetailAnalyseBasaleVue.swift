//
//  DetailAnalyseBasaleVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Page dédiée de l'analyse basale — V3, 6 cartes verticales :
///
///   1. `CarteVerdictBasale`        — constat (sufficient / recentChange / noData)
///   2. `CourbesNocturnesChart`     — graphique avec picker Toutes / Par nuit
///   3. `TimelineNuitsVue`          — périodes analysées (tap → bascule Par nuit)
///   4. `RepartitionNuitsVue`       — répartition zones analysées
///   5. `DoseHistoryCard`           — historique de dose
///   6. `CarteResumeIA`             — texte LLM (masqué si données insuffisantes)
///
/// L'état `mode` et `indexSelectionne` du chart vit ici pour que le
/// callback de la timeline puisse :
///   - basculer le picker du chart sur « Par nuit »
///   - aligner `indexSelectionne` sur la date tappée
///
/// L'analyse reste toujours calculée sur la fenêtre clinique standard
/// de 14 nuits (`kFenetreNuits`).
struct DetailAnalyseBasaleVue: View {

    let analyse: AnalyseBasaleDetail

    @State private var afficherSheetInfo: Bool = false

    // État du chart lifté ici pour que le tap timeline puisse y agir.
    @State private var mode: ModeAffichageGraphiqueBasale = .toutes
    @State private var indexSelectionne: Int = 0

    init(analyse: AnalyseBasaleDetail = .mockStandard14j) {
        self.analyse = analyse
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
                CarteVerdictBasale(analyse: analyse)
                CourbesNocturnesChart(
                    nights: analyse.nightChartData,
                    mode: $mode,
                    indexSelectionne: $indexSelectionne
                )
                TimelineNuitsVue(
                    timeline: analyse.timeline,
                    onNightSelected: { date in basculerSurNuit(date: date) }
                )
                RepartitionNuitsVue(analyse: analyse)
                DoseHistoryCard(changes: analyse.doseHistory)

                if analyse.verdict != .donneesInsuffisantes,
                   let resume = analyse.resumeIA {
                    CarteResumeIA(texte: resume)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Analyse basale")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    afficherSheetInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .accessibilityLabel("Comment fonctionne cette analyse")
                }
            }
        }
        .sheet(isPresented: $afficherSheetInfo) {
            SheetExplicativeBasale()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Tap timeline → bascule sur la nuit

    /// Cherche la nuit dans `nightChartData` qui matche le jour
    /// calendaire de la date tappée, bascule le chart sur « Par nuit »
    /// et positionne `indexSelectionne` dessus.
    private func basculerSurNuit(date: Date) {
        let cal = Calendar.current
        let jourTape = cal.startOfDay(for: date)
        guard let idx = analyse.nightChartData.firstIndex(where: {
            cal.startOfDay(for: $0.date) == jourTape
        }) else {
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            mode = .parNuit
            indexSelectionne = idx
        }
    }
}

// MARK: - Carte résumé IA

/// Carte LLM — texte court (~5 lignes) résumant le verdict en langage
/// naturel + disclaimer « Contenu généré par IA, à vérifier. ».
private struct CarteResumeIA: View {

    let texte: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(texte)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Text("Contenu généré par IA, à vérifier.")
                .font(.caption.italic())
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Résumé généré par IA. \(texte). Contenu généré par IA, à vérifier.")
    }
}

// MARK: - Aperçus

#Preview("Page - Normal (verdict sufficient)") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockStandard14j)
    }
}

#Preview("Page - Recent change") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockRecentChange)
    }
}

#Preview("Page - No data") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockNoData)
    }
}

#Preview("Page - Basale adaptée") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockAdaptee)
    }
}

#Preview("Sheet explicative") {
    SheetExplicativeBasale()
}
