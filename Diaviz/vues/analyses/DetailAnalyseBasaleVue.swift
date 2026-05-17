//
//  DetailAnalyseBasaleVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Page dédiée de l'analyse basale — assemble 5 cartes :
///
///   1. `CarteVerdictBasale`        — verdict + pente + contexte + dose
///   2. `TimelineNuitsVue`          — timeline 14 nuits (incluses / exclues)
///   3. `CourbesNocturnesChart`     — superposition des nuits + tendance
///   4. `RepartitionNuitsVue`       — barre segmentée + métriques détaillées
///   5. `CarteResumeIA`             — texte LLM (masquée si données insuffisantes)
///
/// Cette structure en cartes (verdict → timeline → graphique →
/// décomposition → résumé LLM) sert de **template** pour les futures
/// pages d'analyse (sport, glucides, post-sport…). L'analyse est
/// toujours calculée sur la fenêtre clinique standard de 14 nuits
/// (`kFenetreNuits`) — pas de picker de période, mais une timeline
/// visuelle qui montre lesquelles ont été incluses.
struct DetailAnalyseBasaleVue: View {

    let analyse: AnalyseBasaleDetail

    @State private var afficherSheetInfo: Bool = false

    init(analyse: AnalyseBasaleDetail = .mockStandard14j) {
        self.analyse = analyse
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                CarteVerdictBasale(analyse: analyse)
                TimelineNuitsVue(timeline: analyse.timeline)
                CourbesNocturnesChart(analyse: analyse)
                RepartitionNuitsVue(analyse: analyse)

                if analyse.verdict != .donneesInsuffisantes,
                   let resume = analyse.resumeIA {
                    CarteResumeIA(texte: resume)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
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
}

// MARK: - Carte 5 — résumé IA

/// Carte LLM — texte court (~5 lignes) résumant le verdict en langage
/// naturel + disclaimer « Contenu généré par IA, à vérifier. ».
///
/// Séparée en composant interne plutôt qu'inline parce qu'on s'attend
/// à la réutiliser sur les futures pages d'analyse (chaque verdict aura
/// son propre texte LLM, mais le contenant restera identique : texte
/// body secondary + disclaimer).
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

#Preview("Timeline - 14 jours standard") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockStandard14j)
    }
}

#Preview("Timeline - Après changement de dose") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockChangementDose)
    }
}

#Preview("Basale - Adaptée") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockAdaptee)
    }
}

#Preview("Basale - Trop basse") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockTropBasse)
    }
}

#Preview("Basale - Données insuffisantes") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockInsuffisant)
    }
}

#Preview("Sheet explicative") {
    SheetExplicativeBasale()
}
