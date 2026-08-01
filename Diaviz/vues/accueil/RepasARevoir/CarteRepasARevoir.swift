//
//  CarteRepasARevoir.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Charts
import SwiftUI

/// Carte détaillée d'un repas à revoir — **pleine largeur**, affichée en tête
/// de la section accueil (le repas actuellement étendu, voir
/// `SectionRepasARevoir`). Les autres repas du groupe sont rendus par
/// `LigneRepasARevoir` (forme compacte) ; un tap dessus fait morpher les deux.
///
/// Structure verticale :
///   1. En-tête — **moment de la journée** en titre (pas l'aliment : les noms
///      CIQUAL bruts sont illisibles, « Pain de mie brioché, préemballé ») +
///      date/heure de la dernière occurrence à droite, pour distinguer deux
///      cartes qui partagent le même moment.
///   2. Ligne d'aliments — icônes (photo OFF ou emoji), tronquée avec un
///      badge « +N », et le compteur d'occurrences en pill à droite.
///   3. Badges — ajustements, contexte libre.
///   4. Graphe — nuage des courbes passées + courbe « dernière fois »
///      colorée, faits du hub superposés, axe Y à droite (repères 70/180).
///   5. Pied — verdict de l'événement + ratio appliqué.
///   6. Légende des événements présents (type explicite : bolus/correction/
///      lente/repas/sport, jamais juste un nombre).
struct CarteRepasARevoir: View {

    let repas: RepasARevoir

    private static let maxIconesAliments = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete
            ligneAliments
            badges
            graphe
            pied
            legendeEvenements
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibilite)
    }

    // MARK: - En-tête

    /// Moment de la journée en grand, date/heure de la dernière occurrence à
    /// droite. Plus d'emoji ni de nom d'aliment ici : c'est la ligne
    /// d'aliments juste en dessous qui les montre, à l'échelle d'une icône
    /// par aliment plutôt qu'un nom souvent illisible tel quel (CIQUAL brut).
    private var entete: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(repas.libelleSection.isEmpty ? "Repas" : repas.libelleSection)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(repas.libelleDate)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Ligne d'aliments

    /// Icônes des aliments (photo OFF si présente, sinon emoji), tronquée à
    /// `maxIconesAliments` avec un badge « +N » sinon, et le compteur
    /// d'occurrences en pill à droite (« ×3 ») — absent pour un repas isolé.
    private var ligneAliments: some View {
        HStack(spacing: 6) {
            ForEach(Array(repas.aliments.prefix(Self.maxIconesAliments))) { aliment in
                iconeAliment(aliment)
            }
            let reste = repas.aliments.count - Self.maxIconesAliments
            if reste > 0 {
                Text("+\(reste)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Spacer(minLength: 4)

            if repas.nombreOccurrences > 1 {
                Text("×\(repas.nombreOccurrences)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func iconeAliment(_ aliment: Aliment) -> some View {
        Group {
            if let url = aliment.imageURL {
                ImageProduit(url: url, coinArrondi: 8)
            } else {
                Text(aliment.emoji)
                    .font(.title3)
            }
        }
        .frame(width: 30, height: 30)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Badges

    /// Ajustements (bleu sport / violet classique), contexte libre (orange).
    /// Toujours affichés, quel que soit le verdict — jamais un filtre, juste
    /// le contexte factuel.
    @ViewBuilder
    private var badges: some View {
        if !repas.badgesAjustements.isEmpty || repas.contexteAffiche != nil {
            HStack(spacing: 6) {
                ForEach(repas.badgesAjustements) { item in
                    badge(item.libelle,
                          background: (item.estSport ? Color.blue : Color.purple).opacity(0.15),
                          foreground: item.estSport ? .blue : .purple)
                }
                if let contexte = repas.contexteAffiche {
                    badge(contexte, background: Color.orange.opacity(0.18), foreground: .orange)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        }
    }

    private func badge(_ texte: String, background: Color, foreground: Color) -> some View {
        Text(texte)
            .font(.caption)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
    }

    // MARK: - Graphe

    /// Largeur réservée à la colonne d'axe Y à droite du graphe.
    private static let largeurAxeY: CGFloat = 32

    /// Graphe 110pt : bandes de sport en fond, nuage gris des occurrences
    /// passées, courbe « dernière fois » colorée, marqueurs d'événements posés
    /// **sur** la courbe (comme Santé), marqueur du pic/hypo, et **axe Y à
    /// droite** avec repères 70/180 — sans lui, impossible de lire à quelle
    /// valeur exacte un point de la courbe se trouve.
    ///
    /// Domaine Y **adaptatif** (`repas.domaineY`) et fenêtre **4h** (0…240 min,
    /// `repas.pointsDerniereFois` est déjà tronqué à cet horizon) : une hypo
    /// tardive ne sort plus du cadre.
    private var graphe: some View {
        HStack(spacing: 6) {
            Chart {
                // Bandes de sport en fond — dessinées avant tout le reste
                // pour rester derrière les courbes.
                ForEach(repas.evenements.filter { $0.genre == .sport }) { evenement in
                    RectangleMark(
                        xStart: .value("Début", evenement.minutes),
                        xEnd: .value("Fin", evenement.minutes + (evenement.dureeMinutes ?? 0))
                    )
                    .foregroundStyle(Color.green.opacity(0.12))
                }

                RuleMark(y: .value("Cible haute", 180))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

                if repas.aHypoDansCourbes {
                    RuleMark(y: .value("Seuil hypo", 70))
                        .foregroundStyle(Color.red.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }

                // Nuage gris : une série distincte par occurrence passée,
                // sinon SwiftCharts les relie en une seule polyligne.
                ForEach(Array(repas.pointsOccurrencesPassees.enumerated()), id: \.offset) { idx, courbe in
                    ForEach(courbe) { point in
                        LineMark(
                            x: .value("T", point.minutes),
                            y: .value("G", point.glycemie),
                            series: .value("Occurrence", "passee-\(idx)")
                        )
                        .foregroundStyle(Color.secondary.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .interpolationMethod(.catmullRom)
                    }
                }

                // Courbe de la dernière fois.
                ForEach(repas.pointsDerniereFois) { point in
                    LineMark(
                        x: .value("T", point.minutes),
                        y: .value("G", point.glycemie),
                        series: .value("Occurrence", "derniere")
                    )
                    .foregroundStyle(repas.couleurSeverite)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }

                // Marqueurs d'événements ponctuels, posés sur la courbe à
                // leur instant — le sport est déjà rendu en bande de fond.
                ForEach(repas.evenements.filter { $0.genre != .sport }) { evenement in
                    PointMark(
                        x: .value("T", evenement.minutes),
                        y: .value("G", glycemie(a: evenement.minutes))
                    )
                    .foregroundStyle(evenement.couleur)
                    .symbolSize(60)
                    .symbol {
                        Circle()
                            .fill(evenement.couleur)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                    }
                }

                // Événement principal (pic ou minimum en hypo) — annoté.
                PointMark(
                    x: .value("T", repas.evenementMinutes),
                    y: .value("G", repas.evenementValeur)
                )
                .foregroundStyle(repas.couleurSeverite)
                .symbolSize(28)
                .annotation(position: .top, spacing: 2) {
                    Text("\(Int(repas.evenementValeur.rounded()))")
                        .font(.caption2.bold())
                        .foregroundStyle(repas.couleurSeverite)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 60, 120, 180, 240]) { value in
                    AxisValueLabel {
                        if let minutes = value.as(Int.self) {
                            Text(minutes == 0 ? "repas" : "\(minutes / 60)h")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXScale(domain: 0...RepasARevoir.fenetreAffichageMinutes)
            .chartYScale(domain: repas.domaineY)

            // Axe Y dédié à droite, en Chart "fantôme" partageant le même
            // domaine — pattern déjà utilisé par les graphes journaliers
            // (repas, sport, médications) pour un axe fixe qui ne défile pas.
            axeY
        }
        .frame(height: 110)
    }

    /// Bande d'axe Y fixe — repères 70/180 uniquement (les seuils qui
    /// comptent), pas une graduation régulière qui ajouterait du bruit sans
    /// donner plus d'info utile qu'"à quelle valeur est ce point".
    private var axeY: some View {
        let domaine = repas.domaineY
        let reperes = [180.0, 70.0].filter { domaine.contains($0) }
        return Chart {
            RuleMark(y: .value("min", domaine.lowerBound)).opacity(0)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: domaine)
        .chartYAxis {
            AxisMarks(position: .trailing, values: reperes) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(width: Self.largeurAxeY)
        .accessibilityHidden(true)
    }

    /// Glycémie de la courbe « dernière fois » au point le plus proche d'un
    /// instant donné — sert à poser les marqueurs d'événements **sur** la
    /// courbe plutôt qu'en bas du cadre. Repli au milieu du domaine si la
    /// courbe est vide (ne devrait pas arriver : une carte sans courbe n'est
    /// jamais construite).
    private func glycemie(a minutes: Int) -> Double {
        guard let proche = repas.pointsDerniereFois.min(by: {
            abs($0.minutes - minutes) < abs($1.minutes - minutes)
        }) else {
            return (repas.domaineY.lowerBound + repas.domaineY.upperBound) / 2
        }
        return proche.glycemie
    }

    // MARK: - Pied

    /// Verdict à gauche, ratio appliqué à droite. Le ratio remplace les
    /// glucides bruts : la quantité seule ne dit rien sans la dose en face,
    /// alors que « 1u/10g » est directement comparable au ratio du profil.
    private var pied: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(repas.symboleEvenement)
                    .font(.caption.bold())
                Text(repas.libelleEvenement)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .foregroundStyle(repas.couleurSeverite)

            Spacer(minLength: 4)

            if let ratio = repas.ratioFormate {
                Text(ratio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Légende des événements

    /// Pastille + libellé (déjà explicite : « Bolus repas », « Correction »,
    /// « Lente »…) pour chaque fait superposé au graphe. Taille `.caption`
    /// (pas `.caption2`) : à `.caption2` la légende précédente était
    /// illisible sur un repas avec plusieurs événements.
    @ViewBuilder
    private var legendeEvenements: some View {
        if !repas.evenements.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(repas.evenements) { evenement in
                    HStack(spacing: 6) {
                        Image(systemName: evenement.symbole)
                            .font(.system(size: 10))
                            .foregroundStyle(evenement.couleur)
                            .frame(width: 14)
                        Text(evenement.libelle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Accessibilité

    private var libelleAccessibilite: String {
        let nom = repas.libelleSection.isEmpty ? "Repas" : repas.libelleSection
        let badges = (repas.badgesAjustements.map(\.libelle) + [repas.contexteAffiche])
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let contexte = badges.isEmpty ? "" : " \(badges)."
        let ratio = repas.ratioFormate.map { " Ratio appliqué \($0)." } ?? ""
        let evenements = repas.evenements.isEmpty
            ? ""
            : " Pendant la fenêtre : " + repas.evenements.map(\.libelle).joined(separator: ", ") + "."
        return "\(nom), \(repas.libelleDate). \(repas.nombreOccurrences) fois enregistré.\(contexte) "
            + "\(repas.libelleEvenement).\(ratio)\(evenements)"
    }
}

// MARK: - Aperçus

#Preview("Carte - Big Mac hyper") {
    CarteRepasARevoir(repas: .mockBigMac)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Pad Thaï hypo") {
    CarteRepasARevoir(repas: .mockPadThai)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Carte - Sombre") {
    CarteRepasARevoir(repas: .mockPizza)
        .padding()
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
