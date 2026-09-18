//
//  DetailAnalyseBasaleVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftData
import SwiftUI

/// Page « Analyse du coucher » — hub des deux sous-analyses du coucher,
/// parcourues via les **pills** :
///
///   1. **Tendance basale** (B1)     — verdict, courbes, timeline, répartition,
///      historique de dose, résumé IA
///   2. **Hypos au coucher** (B2+B3) — fusion endormissement + corrections,
///      focus hypo : métriques comptées, soirs listés, « Comparer à ce soir »
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
    /// B1 fournit la catégorie de nuit affichée dans la sheet détail de soirée.
    private var hyposCoucher: AnalyseHyposCoucher {
        CalculHyposCoucher.analyser(
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

    /// Service de lecture des stades de sommeil HealthKit — instance propre à
    /// cette page (l'autorisation elle-même est demandée une fois au boot de
    /// l'app, voir `AppTabVues`). Lecture à la demande, jamais persistée.
    @State private var sleepService = HealthKitSleepService()
    /// Stades de sommeil de la nuit actuellement affichée en vue « Par
    /// nuit » — `[]` par défaut : overlay absent tant que rien n'est chargé
    /// (dégradation gracieuse, jamais de bande approximative).
    @State private var sleepStages: [SleepStageInterval] = []

    @Environment(\.modelContext) private var modelContext

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
        .task(id: indexSelectionne) { await chargerStadesSommeil() }
    }

    /// Recharge les stades de sommeil de la nuit sélectionnée. Silencieux et
    /// dégradé : réglage désactivé, HealthKit indisponible (simulateur) ou
    /// aucune donnée cette nuit-là → `sleepStages` reste `[]`, l'overlay ne
    /// s'affiche simplement pas.
    private func chargerStadesSommeil() async {
        guard ProfilService.shared.profil.preferencesAvancees.overlaySommeilActive ?? true,
              HealthKitSleepService.disponible,
              let nuit = analyse.nightChartData.indices.contains(indexSelectionne)
                ? analyse.nightChartData[indexSelectionne] : nil,
              let debut = nuit.glucoseValues.first?.time,
              let fin = nuit.glucoseValues.last?.time
        else {
            sleepStages = []
            return
        }
        sleepStages = await sleepService.stades(sur: debut...fin)
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
        // Trois groupes nommés plutôt que six cartes au même écart : sans
        // titres, rien ne dit lesquelles répondent à la même question. Les
        // cartes gardent leur en-tête interne — il précise le contenu
        // (« Glycémie nocturne »), le titre de groupe dit l'intention
        // (« Nuit par nuit ») — sauf la carte verdict, qui n'en a pas.
        //
        // 8pt à l'intérieur d'un groupe, 24 entre deux : c'est l'écart qui
        // porte l'information, pas une ligne de séparation.
        VStack(alignment: .leading, spacing: 24) {
            EnTeteAnalyse(
                surtitre: "Analyse du coucher",
                titre: "Tendance basale",
                accroche: "La pente de vos nuits profondes, mesurée depuis votre prise de lente.",
                ambiance: .nuit
            )

            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Verdict")
                CarteVerdictBasale(analyse: analyse)
            }

            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Nuit par nuit")
                CourbesNocturnesChart(
                    nights: analyse.nightChartData,
                    mode: $mode,
                    indexSelectionne: $indexSelectionne,
                    chargePour: chargeContinue(pour:),
                    sleepStages: sleepStages
                )
                TimelineNuitsVue(
                    timeline: analyse.timeline,
                    onNightSelected: { date in basculerSurNuit(date: date) }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Vue d'ensemble")
                RepartitionNuitsVue(analyse: analyse)
                DoseHistoryCard(changes: analyse.doseHistory)
            }

            // Résumé et guide restent sans titre : ce sont des compléments de
            // lecture, pas une quatrième question posée aux données.
            VStack(alignment: .leading, spacing: 12) {
                if analyse.verdict != .donneesInsuffisantes,
                   let resume = analyse.resumeIA {
                    CarteResumeIA(texte: resume)
                }

                boutonGuide
            }
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

    /// Charge d'activité des 45 jours précédant `nuit` — même signal que
    /// l'accueil et le détail de soirée (`CalculChargeContinue`), pour lire
    /// le verdict basale de cette nuit avec le même contexte (dette
    /// technique B1, doc Eraser « B1 — Détection basale », V2 priorité
    /// haute). Calculé à la demande (dataset petit, coût négligeable).
    private func chargeContinue(pour nuit: Date) -> SyntheseChargeContinue {
        let borne = Calendar.current.date(byAdding: .day, value: -45, to: nuit) ?? nuit
        let descripteur = FetchDescriptor<ActiviteSportive>(
            predicate: #Predicate { $0.dateDebut >= borne && $0.dateDebut <= nuit }
        )
        let activites = (try? modelContext.fetch(descripteur)) ?? []
        let entrees = activites.map { (debut: $0.dateDebut, dureeMin: $0.dureeMinutes, intensite: $0.intensite) }
        return CalculChargeContinue.analyser(activites: entrees, maintenant: nuit)
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
