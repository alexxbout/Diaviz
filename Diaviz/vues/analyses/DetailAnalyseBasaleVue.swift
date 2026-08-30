//
//  DetailAnalyseBasaleVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Page « Analyse du coucher » — hub des deux sous-analyses du coucher,
/// parcourues via les **pills** :
///
///   1. **Tendance basale** (B1)     — verdict, courbes, timeline, répartition,
///      historique de dose, résumé IA
///   2. **Hypos au coucher** (B2+B3) — fusion endormissement + corrections,
///      focus hypo : chiffre honnête, situations minées, soirs listés,
///      « Comparer à ce soir »
///
/// En-tête : rangée de **pills draguables** (`PillsCoucher`) posée **fixe** au
/// dessus du contenu scrollable.
///
/// L'état `mode` / `indexSelectionne` du chart B1 vit ici pour que le tap
/// timeline puisse basculer le picker sur « Par nuit » et aligner la nuit.
struct DetailAnalyseBasaleVue: View {

    let analyse: AnalyseBasaleDetail
    let endormissement: AnalyseEndormissement
    let corrections: AnalyseCorrections

    /// Fusion B2+B3 dérivée à la volée (calcul pur, instantané) — la timeline
    /// B1 alimente le facteur « nuit descendante » des situations.
    private var hyposCoucher: AnalyseHyposCoucher {
        CalculSituationsCoucher.analyser(
            endormissement: endormissement,
            corrections: corrections,
            timeline: analyse.timeline,
            changementDoseRecent: analyse.changementDoseRecent
        )
    }

    /// Appelé à l'apparition de la page avec le snapshot `analyse`
    /// **réellement affiché** — le parent (`CarteAnalyseCoucher`) y marque ce
    /// verdict précis comme vu (efface le badge de l'onglet Analyses et le
    /// point « nouveau » de la carte sommaire). Marquer d'après ce snapshot
    /// plutôt que le service live évite qu'un recalcul concurrent (déclenché
    /// par un retour sur l'onglet Analyses) invalide la marque juste posée.
    var onApparition: ((AnalyseBasaleDetail) -> Void)? = nil

    // Page affichée (index dans `SousAnalyseCoucher.allCases`).
    @State private var selection: Int = 0

    // État du chart B1 lifté ici pour que le tap timeline puisse y agir.
    @State private var mode: ModeAffichageGraphiqueBasale = .toutes
    @State private var indexSelectionne: Int = 0

    /// Guide de lecture B1, ouvert depuis le bouton en pied de page.
    @State private var afficherGuide = false

    private let sections = SousAnalyseCoucher.allCases

    /// Sous-analyse actuellement affichée.
    private var pageCourante: SousAnalyseCoucher {
        sections[min(selection, sections.count - 1)]
    }

    /// Pills dérivées des sections (icône + titre). Toutes teintées de la même
    /// couleur — celle de la première section (violet) — pour un sélecteur
    /// visuellement homogène.
    private var pills: [PillCoucher] {
        let teinte = sections.first?.couleur ?? .indigo
        return sections.enumerated().map { index, s in
            PillCoucher(id: index, icone: s.icone, titre: s.titre, couleur: teinte)
        }
    }

    /// Aucune valeur par défaut : les snapshots mockés ne doivent pas être
    /// atteignables depuis le chemin de production — un appelant qui oublie un
    /// argument afficherait un faux constat. Les previews passent leurs
    /// fixtures explicitement.
    init(analyse: AnalyseBasaleDetail,
         endormissement: AnalyseEndormissement,
         corrections: AnalyseCorrections,
         onApparition: ((AnalyseBasaleDetail) -> Void)? = nil) {
        self.analyse = analyse
        self.endormissement = endormissement
        self.corrections = corrections
        self.onApparition = onApparition
    }

    var body: some View {
        // Pills flottantes FIXES en overlay ; le contenu défile DESSOUS pour
        // donner de la matière au Liquid Glass (sinon posé sur le gris plat, il
        // paraît terne). Le contenu est décalé de la hauteur des pills pour ne
        // pas démarrer caché derrière elles au repos.
        ScrollView(.vertical) {
            contenuPage
                .padding(.top, PillsCoucher.hauteur + 24)
                .padding(.bottom, 28)
                .animation(.easeInOut(duration: 0.22), value: selection)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) {
            PillsCoucher(selection: $selection, items: pills)
                .padding(.top, 4)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Analyse du coucher")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { onApparition?(analyse) }
    }

    // MARK: - Contenu de la page sélectionnée

    /// Contenu de la sous-analyse courante. Le `.id(selection)` le recrée à
    /// chaque changement de page → transition d'opacité entre sections.
    private var contenuPage: some View {
        VStack(spacing: 12) {
            switch pageCourante {
            case .basale:        contenuBasale
            case .hyposCoucher:
                PageHyposCoucher(
                    analyse: hyposCoucher,
                    nuitsB1: analyse.nightChartData
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(selection)
        .transition(.opacity)
    }

    /// Contenu B1 — verdict, courbes, timeline, répartition, historique de
    /// dose et résumé IA. La carte « Sur quoi se base ce verdict » a été
    /// fondue dans la carte verdict : elle répétait nuits analysées, dérive
    /// moyenne et nuits exclues ; seuls ses motifs étaient uniques.
    private var contenuBasale: some View {
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

            boutonGuide
        }
    }

    /// Pied de page B1 — ouvre le guide de lecture. Placé ici plutôt qu'en
    /// barre de navigation : la page porte deux analyses, un bouton de barre
    /// serait ambigu, et on le découvre naturellement en finissant de lire.
    private var boutonGuide: some View {
        Button {
            afficherGuide = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                Text("Comment lire cette analyse")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $afficherGuide) {
            SheetGuideTendanceBasale()
        }
    }

    // MARK: - Helpers

    /// Cherche la nuit dans `nightChartData` qui matche le jour calendaire
    /// de la date tappée, bascule le chart sur « Par nuit » et positionne
    /// `indexSelectionne` dessus.
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
        .clipShape(NiveauCarte.carte.forme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Résumé généré par IA. \(texte). Contenu généré par IA, à vérifier.")
    }
}


// MARK: - Aperçus

#if DEBUG
#Preview("Page - Normal (verdict sufficient)") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockStandard14j, endormissement: .mock, corrections: .mock)
    }
}

#Preview("Page - Pipeline réel (synthétique)") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: CalculAnalyseBasale.apercu(), endormissement: .mock, corrections: .mock)
    }
}

#Preview("Page - Recent change") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockRecentChange, endormissement: .mock, corrections: .mock)
    }
}

#Preview("Page - No data") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockNoData, endormissement: .mock, corrections: .mock)
    }
}

#Preview("Page - Basale adaptée") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockAdaptee, endormissement: .mock, corrections: .mock)
    }
}

#Preview("Sheet explicative") {
    SheetExplicativeBasale()
}
#endif
