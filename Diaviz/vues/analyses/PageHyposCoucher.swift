//
//  PageHyposCoucher.swift
//  diaviz
//

import SwiftUI

/// Section **« Hypos au coucher »** de la page « Analyse du coucher » —
/// fusion des analyses B2 (endormissement) et B3 (corrections du soir),
/// **focus hypo** (l'événement dangereux ; l'issue « insuffisant » de B3
/// reste visible au détail mais ne pilote pas la page).
///
/// Structure purement rétrospective :
///   1. Carte de métriques (hypos, dont avec rechute, hypos évitées + glucides)
///   2. Bouton « Comparer à ce soir » → sheet de recherche (saisie glycémie)
///   3. Soirs analysés (filtre hypos/tous, tri date/glycémie, liste)
///
/// Le « ce soir » vit entièrement dans la sheet : la glycémie CGM arrive avec
/// ~3h de retard, aucune détection automatique n'est possible ici.
///
/// La section « Situations observées » (croisements de facteurs minés par
/// énumération) a été **retirée** en août 2026 : un facteur pris isolément,
/// sans mise en regard des autres analyses, ne disait rien d'actionnable et
/// alourdissait la page. Les métriques comptées l'ont remplacée.
struct PageHyposCoucher: View {

    let analyse: AnalyseHyposCoucher
    /// Nuits B1 (courbes, zones, events) — alimentent la sheet détail de
    /// soirée. Vide en preview → sheet en dégradation gracieuse.
    var nuitsB1: [NightChartData] = []

    /// Filtre de la liste des soirs. Défaut « hypos » quand il y en a, sinon
    /// « tous » (une liste vide sous un filtre sélectionné serait déroutante).
    enum FiltreSoirs { case hypos, tous }
    @State private var filtre: FiltreSoirs = .hypos

    /// Tri de la liste — date (plus récent d'abord, défaut) ou glycémie
    /// (croissante).
    enum TriSoirs: CaseIterable {
        case date, glycemie

        var libelle: String {
            switch self {
            case .date:     return "Date"
            case .glycemie: return "Glycémie"
            }
        }

        var symbole: String {
            switch self {
            case .date:     return "calendar"
            case .glycemie: return "drop"
            }
        }
    }
    @State private var tri: TriSoirs = .date

    @State private var afficherComparer = false
    @State private var soirSelectionne: SoirCoucher?

    @Environment(\.dynamicTypeSize) private var tailleTexte

    /// Filtre effectif : bascule sur « tous » s'il n'y a aucune hypo à montrer.
    private var filtreEffectif: FiltreSoirs {
        analyse.totalHypos == 0 ? .tous : filtre
    }

    var body: some View {
        // Deux groupes nommés, même grammaire que la tendance basale : 8pt
        // à l'intérieur d'un groupe, 24 entre deux. Le bouton de comparaison
        // rejoint la liste des soirs — il ouvre la recherche du soir le plus
        // proche, il appartient donc au même geste qu'explorer les soirées.
        VStack(alignment: .leading, spacing: 24) {
            EnTeteAnalyse(
                surtitre: "Analyse du coucher",
                titre: "Hypos au coucher",
                accroche: "Ce qui suit vos soirées, selon la façon dont elles commencent.",
                ambiance: .coucher
            )

            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Vue d'ensemble")
                carteMetriques
            }

            // Hub encore vide : la carte porte déjà le message, inutile
            // d'empiler un bouton de recherche sans corpus ni une liste vide.
            if analyse.totalSoirs > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    TitreSection(texte: "Soirée par soirée")
                    boutonComparer
                    sectionSoirs
                }
            }
        }
        .sheet(isPresented: $afficherComparer) {
            SheetComparerCeSoir(doseActuelle: analyse.doseActuelle)
        }
        .sheet(item: $soirSelectionne) { soir in
            SheetDetailSoiree(
                soir: soir,
                nuitB1: nuitB1(pour: soir),
                changementDoseRecent: analyse.changementDoseRecent
            )
        }
    }

    /// Nuit B1 correspondant à un soir, par **jour métabolique** (`dateNuit`,
    /// même clé que `NightChartData.date`).
    ///
    /// L'ancien rapprochement testait si la fenêtre de coucher d'une nuit
    /// contenait `soir.date` — faux pour tout soir B2, dont la `date` est
    /// minuit : la fenêtre de la veille (lente ~23h → +2h) contient minuit,
    /// donc chaque soir affichait la nuit précédente.
    private func nuitB1(pour soir: SoirCoucher) -> NightChartData? {
        let cal = Calendar.current
        return nuitsB1.first { cal.isDate($0.date, inSameDayAs: soir.dateNuit) }
    }

    // MARK: - 1. Carte de métriques

    /// Faits comptés sur la fenêtre analysée. Trois métriques, chacune
    /// recomptable à la main depuis la liste des soirs plus bas — pas une
    /// inférence, pas un score. « Avec rechute » et « évitées » sont des
    /// **dont** et des **à côté**, jamais des chiffres à additionner : le
    /// dénominateur commun est rappelé en en-tête.
    @ViewBuilder
    private var carteMetriques: some View {
        if analyse.totalSoirs == 0 {
            Text("Aucun soir analysable pour l'instant — il faut des nuits avec lente et couverture CGM.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .surfaceCarte()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                enTeteMetriques
                Divider()
                tuiles
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCarte()
        }
    }

    private var enTeteMetriques: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(analyse.totalSoirs) soir\(analyse.totalSoirs > 1 ? "s" : "") analysé\(analyse.totalSoirs > 1 ? "s" : "")")
                .font(.headline)
                .monospacedDigit()
            Text(libelleFenetre)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var libelleFenetre: String {
        if let date = analyse.changementDoseRecent {
            let jour = date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
            return "depuis le changement de dose du \(jour) · lente \(analyse.doseActuelle.formatted()) u"
        }
        return "lente actuelle : \(analyse.doseActuelle.formatted()) u"
    }

    /// Les trois tuiles. Empilées verticalement aux tailles d'accessibilité :
    /// à trois colonnes, les libellés y deviennent illisibles.
    @ViewBuilder
    private var tuiles: some View {
        if tailleTexte.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(metriques, id: \.libelle) { m in
                    tuile(m, alignement: .leading)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(metriques, id: \.libelle) { m in
                    tuile(m, alignement: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private struct Metrique {
        let valeur: Int
        let libelle: String
        let detail: String?
        let symbole: String
        let couleur: Color
    }

    private var metriques: [Metrique] {
        [
            Metrique(
                valeur: analyse.totalHypos,
                libelle: analyse.totalHypos > 1 ? "hypos" : "hypo",
                detail: nil,
                symbole: "arrow.down.right.circle.fill",
                couleur: .red
            ),
            Metrique(
                valeur: analyse.totalRechutes,
                libelle: "avec rechute",
                detail: "resucrage puis nouvelle hypo",
                symbole: "arrow.uturn.down.circle.fill",
                couleur: .red
            ),
            Metrique(
                valeur: analyse.totalHyposEvitees,
                libelle: analyse.totalHyposEvitees > 1 ? "hypos évitées" : "hypo évitée",
                detail: detailHyposEvitees,
                symbole: "shield.lefthalf.filled",
                couleur: .orange
            ),
        ]
    }

    /// Glucides **médians** des préventifs qui ont tenu — « à peu près
    /// combien », pas une dose à reproduire.
    private var detailHyposEvitees: String? {
        guard analyse.totalHyposEvitees > 0 else { return nil }
        guard let g = analyse.glucidesTypiquesHypoEvitee else { return "resucrage préventif" }
        return "préventif · ~\(g) g"
    }

    private func tuile(_ m: Metrique, alignement: HorizontalAlignment) -> some View {
        // Zéro en gris : une métrique à 0 est une bonne nouvelle, pas une
        // alerte — la teinte ne s'allume que s'il y a matière.
        let teinte: Color = m.valeur > 0 ? m.couleur : .secondary
        return VStack(alignment: alignement, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: m.symbole)
                    .font(.footnote)
                    .foregroundStyle(teinte)
                    .accessibilityHidden(true)
                Text("\(m.valeur)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(teinte)
            }
            Text(m.libelle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let detail = m.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.valeur) \(m.libelle)\(m.detail.map { ", \($0)" } ?? "")")
    }

    // MARK: - 2. Comparer à ce soir

    private var boutonComparer: some View {
        Button {
            afficherComparer = true
        } label: {
            Label("Comparer ma glycémie de ce soir", systemImage: "magnifyingglass")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // MARK: - 3. Soirs (filtre segmenté hypos / tous + tri)

    private var soirsVisibles: [SoirCoucher] {
        let base: [SoirCoucher]
        switch filtreEffectif {
        case .hypos: base = analyse.soirsEnHypo
        case .tous:  base = analyse.soirs
        }
        switch tri {
        case .date:     return base.sorted { $0.date > $1.date }
        case .glycemie: return base.sorted { $0.glycemie < $1.glycemie }
        }
    }

    private var sectionSoirs: some View {
        VStack(alignment: .leading, spacing: 10) {
            enTeteSoirs
            if analyse.totalHypos > 0 {
                filtreSegmente
            }

            let visibles = soirsVisibles
            if visibles.isEmpty {
                Text(messageVide)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .surfaceCarte()
            } else {
                VStack(spacing: 8) {
                    ForEach(visibles) { soir in
                        LigneSoirCoucher(soir: soir, onTap: { soirSelectionne = soir })
                    }
                }
            }
        }
    }

    /// Titre + bouton de tri. Le tri est un **bouton bordé lisible** (icône +
    /// critère courant) et non plus une pastille d'icône de 26 pt : la cible
    /// était sous le minimum tapable iOS, et rien n'indiquait le tri actif.
    /// Barre de contrôles de la liste — plus de titre : « Soirs analysés »
    /// répétait le titre de groupe posé juste au-dessus. Le tri reste, c'est
    /// une commande, pas un intitulé.
    private var enTeteSoirs: some View {
        HStack(alignment: .firstTextBaseline) {
            Spacer(minLength: 0)
            menuTri
        }
    }

    private var menuTri: some View {
        Menu {
            Picker("Trier par", selection: $tri) {
                ForEach(TriSoirs.allCases, id: \.self) { valeur in
                    Label(valeur.libelle, systemImage: valeur.symbole).tag(valeur)
                }
            }
        } label: {
            Label(tri.libelle, systemImage: "arrow.up.arrow.down")
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityLabel("Trier les soirs")
        .accessibilityValue(tri == .date ? "Par date" : "Par glycémie")
    }

    /// Segmented natif plutôt qu'une capsule maison : hauteur, typographie et
    /// cible de tap sont celles du système, et il suit Dynamic Type tout seul.
    private var filtreSegmente: some View {
        Picker("Soirs affichés", selection: $filtre) {
            Text("Hypos · \(analyse.totalHypos)").tag(FiltreSoirs.hypos)
            Text("Tous · \(analyse.totalSoirs)").tag(FiltreSoirs.tous)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Cas restant : des soirs analysés, mais aucun ne passe le filtre courant
    /// (le hub vide est traité en amont par `carteMetriques`).
    private var messageVide: String {
        "Aucune hypo sur \(analyse.totalSoirs) soir\(analyse.totalSoirs > 1 ? "s" : "") analysé\(analyse.totalSoirs > 1 ? "s" : "")."
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Hypos au coucher — mock") {
    ScrollView {
        PageHyposCoucher(analyse: .mock)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Hypos au coucher — sans hypo") {
    ScrollView {
        PageHyposCoucher(
            analyse: CalculHyposCoucher.analyser(
                endormissement: .mockSansHypo, corrections: AnalyseCorrections(corrections: []), timeline: []
            )
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Hypos au coucher — avec changement de dose") {
    ScrollView {
        PageHyposCoucher(analyse: .mockRiche)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Hypos au coucher — seulement corrections (pas de B2)") {
    ScrollView {
        PageHyposCoucher(
            analyse: CalculHyposCoucher.analyser(
                endormissement: AnalyseEndormissement(seuilCoucher: 160, doseActuelle: 18, nuits: []),
                corrections: .mock, timeline: []
            )
        )
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
