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

    init(analyse: AnalyseBasaleDetail = .mockStandard14j,
         endormissement: AnalyseEndormissement = .mock,
         corrections: AnalyseCorrections = .mock,
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

    /// Contenu B1 — verdict, fondements, courbes, timeline, répartition,
    /// historique de dose et résumé IA.
    private var contenuBasale: some View {
        VStack(spacing: 12) {
            CarteVerdictBasale(analyse: analyse)
            CarteFondementsVerdict(analyse: analyse)
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

// MARK: - Fondements du verdict (« Sur quoi se base ce verdict »)

/// Bloc factuel sous la carte verdict : explicite les données qui ont produit
/// le verdict B1 — nuits analysées (et depuis quand), pente moyenne nuit
/// profonde, nuits exclues avec motifs, nuits sans CGM. Permet de comprendre
/// d'un coup d'œil le « pourquoi » d'une alerte de basale.
private struct CarteFondementsVerdict: View {

    let analyse: AnalyseBasaleDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sur quoi se base ce verdict")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            ligne(icone: "checkmark.seal.fill", couleur: .green,
                  texte: nuitsAnalyseesTexte, sous: depuisChangement)

            if analyse.nuitsAnalysees > 0 {
                ligne(icone: "chart.xyaxis.line", couleur: .indigo,
                      texte: "Dérive moyenne nuit profonde : \(deriveFmt(analyse.deriveMoyenne)) mg/dL par nuit",
                      sous: nil)
            }

            if analyse.nuitsExclues > 0 {
                ligne(icone: "xmark.circle.fill", couleur: .orange,
                      texte: "\(analyse.nuitsExclues) \(motNuit(analyse.nuitsExclues)) exclue\(analyse.nuitsExclues > 1 ? "s" : "")",
                      sous: nil)
                ForEach(raisonsExclusion, id: \.libelle) { r in
                    sousLigne("\(r.libelle) : \(r.count)")
                }
            }

            if nbSansDonnees > 0 {
                ligne(icone: "wifi.slash", couleur: .secondary,
                      texte: "\(nbSansDonnees) \(motNuit(nbSansDonnees)) sans CGM", sous: nil)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(NiveauCarte.carte.forme)
        .accessibilityElement(children: .combine)
    }

    // MARK: Lignes

    @ViewBuilder
    private func ligne(icone: String, couleur: Color, texte: String, sous: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(couleur)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(texte)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                if let sous {
                    Text(sous)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sousLigne(_ texte: String) -> some View {
        Text(texte)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Dérivés

    private var nuitsAnalyseesTexte: String {
        "\(analyse.nuitsAnalysees) \(motNuit(analyse.nuitsAnalysees)) analysée\(analyse.nuitsAnalysees > 1 ? "s" : "")"
    }

    private var depuisChangement: String? {
        guard let date = analyse.changementDoseRecent else { return nil }
        let lib = date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
        return "depuis le changement de dose du \(lib)"
    }

    /// Répartition des motifs d'exclusion sur la fenêtre comparable
    /// (post-changement de dose, hors nuit en cours) — somme cohérente avec
    /// `nuitsExclues`.
    private var raisonsExclusion: [(libelle: String, count: Int)] {
        var dict: [String: Int] = [:]
        for n in analyse.timeline where !n.avantChangementDose {
            if case .exclue(let r) = n.etat { dict[r.rawValue, default: 0] += 1 }
        }
        return dict.map { (libelle: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var nbSansDonnees: Int {
        analyse.timeline.filter { !$0.avantChangementDose && $0.etat == .sansDonnees }.count
    }

    private func motNuit(_ n: Int) -> String { n > 1 ? "nuits" : "nuit" }

    private func deriveFmt(_ d: Double) -> String {
        String(format: "%+d", Int(d.rounded()))
    }
}

// MARK: - Aperçus

#Preview("Page - Normal (verdict sufficient)") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockStandard14j)
    }
}

#Preview("Page - Pipeline réel (synthétique)") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: CalculAnalyseBasale.apercu())
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
