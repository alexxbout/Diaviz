//
//  CarteRepasARevoir.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Charts
import SwiftUI

/// Carte unitaire de la section « Repas à revoir » — 200×200pt, affichée
/// dans un scroll horizontal sous les insights de l'accueil.
///
/// Structure verticale :
///   1. Titre — emoji + nom de l'aliment principal.
///   2. Sous-titre — nombre d'occurrences enregistrées.
///   3. Mini-graphique Swift Charts — **nuage** des courbes passées
///      en gris + courbe « dernière fois » colorée selon la sévérité.
///   4. Info pic — triangle directionnel + libellé compact.
///   5. Glucides déclarés — fourchette min–max.
///
/// Fond opaque `secondarySystemGroupedBackground` — même surface que
/// les autres cartes standard de l'accueil (insights, lente, grille
/// des métriques) pour homogénéiser le langage visuel de la page.
struct CarteRepasARevoir: View {

    let repas: RepasARevoir

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // MARK: Titre
            // Emoji + nom du plat principal à gauche, nombre d'occurrences
            // en fin de ligne à droite (uniquement si le repas est
            // effectivement récurrent — une carte « Repas avec contexte »,
            // toujours à occurrence unique, n'affiche rien ici).
            HStack(spacing: 4) {
                if let principal = repas.alimentPrincipal {
                    Text(principal.emoji)
                        .font(.subheadline)
                        .accessibilityHidden(true)
                    Text(principal.nom)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                if repas.nombreOccurrences > 1 {
                    Text("×\(repas.nombreOccurrences)")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }

            // MARK: Badges — moment+ratio (neutre), ajustements (bleu sport /
            // violet classique), contexte libre (orange). Toujours affichés,
            // quel que soit le verdict — jamais un filtre, juste le contexte
            // factuel.
            if !repas.libelleSection.isEmpty || !repas.badgesAjustements.isEmpty || repas.contexteAffiche != nil {
                HStack(spacing: 4) {
                    if !repas.libelleSection.isEmpty {
                        badge(repas.libelleSection, background: Color(.tertiarySystemFill), foreground: .secondary)
                    }
                    ForEach(repas.badgesAjustements) { item in
                        badge(item.libelle, background: (item.estSport ? Color.blue : Color.purple).opacity(0.15),
                              foreground: item.estSport ? .blue : .purple)
                    }
                    if let contexte = repas.contexteAffiche {
                        badge(contexte, background: Color.orange.opacity(0.18), foreground: .orange)
                    }
                }
                .lineLimit(1)
            }

            // MARK: Mini-graphique
            // 12pt d'air au-dessus pour que les annotations du pic ne
            // touchent jamais le bloc texte au-dessus, même quand le
            // pic tombe près du bord supérieur du chart.
            mini
                .padding(.top, 12)

            // Spacer flexible : pousse le bloc info pic + glucides au
            // bas de la carte pour éviter une bande de vide en bas
            // (le contenu était aligné `.topLeading` sur 200pt fixe).
            // Résultat : 3 zones — header (titre + occurrences),
            // chart, footer (info pic + glucides).
            Spacer(minLength: 0)

            // MARK: Info pic
            HStack(spacing: 4) {
                Text(repas.symboleEvenement)
                    .font(.caption.bold())
                    .foregroundStyle(repas.couleurSeverite)
                Text(repas.libelleEvenement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // MARK: Glucides déclarés
            Text("Glucides : \(repas.glucidesMin)–\(repas.glucidesMax)g")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 200, height: 200, alignment: .topLeading)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibilite)
    }

    /// Badge compact commun (moment, ajustement, contexte) — capsule teintée,
    /// texte tronqué à une ligne pour rester dans les 200pt de large.
    private func badge(_ texte: String, background: Color, foreground: Color) -> some View {
        Text(texte)
            .font(.caption2)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
    }

    // MARK: - Mini-graphique

    /// Mini-chart 50pt — **nuage** des courbes passées en gris discret
    /// + courbe « dernière fois » colorée selon la sévérité, PointMark
    /// au pic + valeur, RuleMark au seuil 180 et — uniquement quand
    /// une courbe descend en hypo — au seuil 70.
    ///
    /// Plus les courbes grises sont regroupées, plus le repas est
    /// prévisible. Plus elles s'étalent, plus la réponse est chaotique.
    ///
    /// Domaine X figé à `0…180` minutes pour que toutes les cartes
    /// partagent la même largeur temporelle. Domaine Y figé à
    /// `50…300` mg/dL — fenêtre large qui couvre hypo profonde et
    /// hyper sévère, et qui garantit que l'annotation du pic ne sort
    /// jamais du cadre du graphe.
    private var mini: some View {
        Chart {
            // Nuage gris : chaque occurrence passée tracée
            // individuellement. `series` distinct par index pour que
            // SwiftCharts ne les relie pas en une seule ligne.
            ForEach(Array(repas.pointsOccurrencesPassees.enumerated()), id: \.offset) { idx, courbe in
                ForEach(courbe) { point in
                    LineMark(
                        x: .value("T", point.minutes),
                        y: .value("G", point.glycemie),
                        series: .value("Occurrence", "passee-\(idx)")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Courbe dernière fois — plein, colorée selon la sévérité.
            ForEach(repas.pointsDerniereFois) { point in
                LineMark(
                    x: .value("T", point.minutes),
                    y: .value("G", point.glycemie),
                    series: .value("Occurrence", "derniere")
                )
                .foregroundStyle(repas.couleurSeverite)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            // Marqueur de l'événement principal (pic ou min en hypo).
            PointMark(
                x: .value("T", repas.evenementMinutes),
                y: .value("G", repas.evenementValeur)
            )
            .foregroundStyle(repas.couleurSeverite)
            .symbolSize(25)
            .annotation(position: .top, spacing: 2) {
                Text("\(Int(repas.evenementValeur.rounded()))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(repas.couleurSeverite)
            }

            // Seuil 180 mg/dL — repère discret cible / hyper.
            RuleMark(y: .value("Seuil hyper", 180))
                .foregroundStyle(Color.secondary.opacity(0.15))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

            // Seuil 70 mg/dL — affiché **uniquement** quand au moins
            // une courbe descend en hypo. Évite d'encombrer les cartes
            // dont aucune réponse n'approche du seuil hypo.
            if repas.aHypoDansCourbes {
                RuleMark(y: .value("Seuil hypo", 70))
                    .foregroundStyle(Color.red.opacity(0.15))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...180)
        .chartYScale(domain: 50...300)
        .frame(height: 50)
        .accessibilityHidden(true)
    }

    // MARK: - Accessibilité

    /// Synthèse VoiceOver — nom du repas, sévérité, valeur du pic
    /// et fourchette de glucides. Évite de naviguer les sous-éléments.
    private var libelleAccessibilite: String {
        let nom = repas.alimentPrincipal?.nom ?? "Repas"
        let badges = ([repas.libelleSection] + repas.badgesAjustements.map(\.libelle) + [repas.contexteAffiche])
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let contexte = badges.isEmpty ? "" : " \(badges)."
        return "\(nom). \(repas.nombreOccurrences) fois enregistré.\(contexte) "
            + "\(repas.libelleEvenement). Glucides déclarés "
            + "\(repas.glucidesMin) à \(repas.glucidesMax) grammes."
    }
}

// MARK: - Aperçus

#Preview("Carte - Big Mac hyper") {
    CarteRepasARevoir(repas: .mockBigMac)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Pizza hyper sévère") {
    CarteRepasARevoir(repas: .mockPizza)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Sushi en cible") {
    CarteRepasARevoir(repas: .mockSushi)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Pad Thaï hypo") {
    CarteRepasARevoir(repas: .mockPadThai)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Sombre") {
    CarteRepasARevoir(repas: .mockBigMac)
        .padding()
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
