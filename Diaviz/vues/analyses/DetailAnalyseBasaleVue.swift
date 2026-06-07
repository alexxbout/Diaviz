//
//  DetailAnalyseBasaleVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Page « Analyse du coucher » — hub fusionné des trois sous-analyses du
/// coucher, présentées en **accordéon** (`EnTeteSectionCoucher` + contenu) :
///
///   1. **Tendance basale** (B1)      — contenu existant (verdict, courbes,
///      timeline, répartition, historique de dose, résumé IA)
///   2. **Endormissement** (B2)       — tableau des hypos à l'endormissement
///   3. **Corrections du soir** (B3)  — tableau des corrections au coucher
///
/// Toutes les sections sont **fermées par défaut** : seuls les en-têtes
/// (titre + statut glance + ⓘ) sont visibles, donnant un panorama des trois
/// analyses sans scroll. Le détail se déplie à la demande.
///
/// L'état `mode` / `indexSelectionne` du chart B1 vit ici pour que le tap
/// timeline puisse basculer le picker sur « Par nuit » et aligner la nuit.
/// L'analyse basale reste calculée sur la fenêtre clinique de 14 nuits.
struct DetailAnalyseBasaleVue: View {

    let analyse: AnalyseBasaleDetail
    let endormissement: AnalyseEndormissement
    let corrections: AnalyseCorrections

    // Sections ouvertes — vide = toutes fermées (défaut).
    @State private var sectionsOuvertes: Set<SousAnalyseCoucher> = []

    // Sheets explicatives Pourquoi / Quoi / Comment (B2/B3 = placeholders).
    @State private var afficherInfoBasale: Bool = false
    @State private var afficherInfoEndormissement: Bool = false
    @State private var afficherInfoCorrections: Bool = false

    // Sheet de recherche « Comparer à ce soir » (transverse B2/B3).
    @State private var afficherComparaison: Bool = false

    // État du chart B1 lifté ici pour que le tap timeline puisse y agir.
    @State private var mode: ModeAffichageGraphiqueBasale = .toutes
    @State private var indexSelectionne: Int = 0

    init(analyse: AnalyseBasaleDetail = .mockStandard14j,
         endormissement: AnalyseEndormissement = .mock,
         corrections: AnalyseCorrections = .mock) {
        self.analyse = analyse
        self.endormissement = endormissement
        self.corrections = corrections
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                boutonComparer
                sectionBasale
                sectionEndormissement
                sectionCorrections
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Analyse du coucher")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $afficherComparaison) {
            SheetComparerCeSoir(analyse: endormissement)
        }
        .sheet(isPresented: $afficherInfoBasale) {
            SheetExplicativeBasale()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $afficherInfoEndormissement) {
            SheetExplicativePlaceholder(titre: "Endormissement")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $afficherInfoCorrections) {
            SheetExplicativePlaceholder(titre: "Corrections du soir")
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Bouton « Comparer à ce soir » (niveau page)

    private var boutonComparer: some View {
        Button {
            afficherComparaison = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                Text("Comparer ma glycémie du soir").fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo.opacity(0.5))
            }
            .foregroundStyle(.indigo)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.indigo.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityHint("Recherche les nuits passées proches de ta situation de ce soir")
    }

    // MARK: - Section B1 — Tendance basale

    private var sectionBasale: some View {
        VStack(spacing: 0) {
            EnTeteSectionCoucher(
                titre: "Tendance basale",
                etat: etatBasale,
                ouverte: sectionsOuvertes.contains(.basale),
                onInfo: { afficherInfoBasale = true },
                onToggle: { basculer(.basale) }
            )
            if sectionsOuvertes.contains(.basale) {
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
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
        }
    }

    // MARK: - Section B2 — Endormissement

    private var sectionEndormissement: some View {
        VStack(spacing: 0) {
            EnTeteSectionCoucher(
                titre: "Endormissement",
                etat: etatEndormissement,
                ouverte: sectionsOuvertes.contains(.glycemie),
                onInfo: { afficherInfoEndormissement = true },
                onToggle: { basculer(.glycemie) }
            )
            if sectionsOuvertes.contains(.glycemie) {
                TableauEndormissement(analyse: endormissement)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
            }
        }
    }

    // MARK: - Section B3 — Corrections du soir

    private var sectionCorrections: some View {
        VStack(spacing: 0) {
            EnTeteSectionCoucher(
                titre: "Corrections",
                etat: etatCorrections,
                ouverte: sectionsOuvertes.contains(.corrections),
                onInfo: { afficherInfoCorrections = true },
                onToggle: { basculer(.corrections) }
            )
            if sectionsOuvertes.contains(.corrections) {
                TableauCorrections(analyse: corrections)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
            }
        }
    }

    // MARK: - Helpers

    /// Plie/déplie une section avec une animation de hauteur simple
    /// (pas de glissement vertical).
    private func basculer(_ sous: SousAnalyseCoucher) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if sectionsOuvertes.contains(sous) { sectionsOuvertes.remove(sous) }
            else { sectionsOuvertes.insert(sous) }
        }
    }

    /// Statut glance de la section B1, dérivé du verdict basale — même
    /// vocabulaire que la carte sommaire.
    private var etatBasale: EtatSousAnalyse {
        switch analyse.verdict {
        case .adaptee:
            return .resultat(libelle: "Adaptée", ton: .positif)
        case .tropHaute, .tropBasse:
            return .resultat(libelle: "À revoir", ton: .attention)
        case .donneesInsuffisantes:
            return .enAttente
        }
    }

    /// Statut glance de la section B2 — compte d'hypos à l'endormissement,
    /// sinon « Aucune récente ». B2 ne se gate pas : il remonte des faits.
    private var etatEndormissement: EtatSousAnalyse {
        let n = endormissement.nombreHypos
        guard n > 0 else { return .resultat(libelle: "Aucune récente", ton: .neutre) }
        return .resultat(libelle: n == 1 ? "1 hypo" : "\(n) hypos", ton: .attention)
    }

    /// Statut glance de la section B3 — compte de corrections du soir, neutre
    /// (B3 expose des faits, ne juge pas).
    private var etatCorrections: EtatSousAnalyse {
        let n = corrections.nombre
        guard n > 0 else { return .enAttente }
        // Le mot « corrections » serait redondant avec le titre de section :
        // on n'affiche que le compte.
        return .resultat(libelle: "\(n)", ton: .neutre)
    }

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
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Résumé généré par IA. \(texte). Contenu généré par IA, à vérifier.")
    }
}

// MARK: - Placeholder sheet explicative (B2 / B3)

/// Sheet explicative provisoire (Pourquoi / Quoi / Comment) pour B2 / B3,
/// en attendant la généralisation de `SheetExplicativeBasale`.
private struct SheetExplicativePlaceholder: View {

    let titre: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre)
                .font(.title2.bold())
            Text("Pourquoi / Quoi / Comment — contenu explicatif à rédiger.")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
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
