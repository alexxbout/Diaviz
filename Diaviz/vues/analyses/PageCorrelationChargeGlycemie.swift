//
//  PageCorrelationChargeGlycemie.swift
//  diaviz
//

import Charts
import SwiftUI

/// Page d'analyse « Charge et glycémie » — épisode de charge en cours,
/// chronologie de la charge (vs référence) face au score GRI sur
/// `CalculCorrelationChargeTIR.nombreSemaines` semaines, état des réglages
/// et épisodes passés comparables (C1). Co-occurrence affichée, jamais une
/// cause affirmée.
struct PageCorrelationChargeGlycemie: View {

    let synthese: SyntheseCorrelationChargeTIR
    /// Charge active (`CalculChargeActive`) — `nil` tant que le premier
    /// calcul n'a pas abouti (lecture Apple Santé en cours).
    var chargeActive: SyntheseChargeActive? = nil
    /// Épisodes de charge (C1) — `nil` avant le premier calcul.
    var episodes: SyntheseEpisodesCharge? = nil

    private let teinteCharge = Color.orange
    private let teinteScore = Color.blue

    /// Semaine sélectionnée au tap/drag sur la chronologie — `nil` par
    /// défaut, la carte n'affiche alors rien de plus que le graphique.
    @State private var semaineSelectionnee: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TitreSectionEpisode(texte: "En ce moment")
                CarteEpisodeEnCours(episode: episodes?.enCours, precedent: episodes?.precedent, charge: chargeActive)
                TitreSectionEpisode(texte: "Chronologie")
                chronologie
                if let episodes, !episodes.etatsActuels.isEmpty {
                    TitreSectionEpisode(texte: "Vos réglages")
                    SectionReglagesActuels(synthese: episodes)
                }
                if let episodes, episodes.enCours != nil {
                    TitreSectionEpisode(texte: "Les fois précédentes")
                    SectionFoisPrecedentes(synthese: episodes)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Charge et glycémie")
        .navigationBarTitleDisplayMode(.inline)
        .boutonCriteresEpisodes()
    }

    // MARK: - Chronologie

    /// Haut de l'échelle de charge : marge au-dessus de la plus haute barre
    /// (place pour son %), et jamais moins de 1,5 pour que la ligne de
    /// référence (1) ne colle pas au sommet.
    private var maxCharge: Double {
        max((synthese.semaines.compactMap(\.indiceCharge).max() ?? 0) * 1.2, 1.5)
    }

    private func estAttenuee(_ semaine: Date) -> Bool {
        semaineSelectionnee != nil && semaineSelectionnee != semaine
    }

    private var chronologie: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Une seule ligne ; si elle ne tient pas (grande police), repli
            // sur deux lignes plutôt qu'un texte tronqué.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    legendeCharge
                    legendeScore
                    legendeReference
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        legendeCharge
                        legendeScore
                    }
                    legendeReference
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            graphique

            aideLecture
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    /// Un seul graphique : barres de charge (lues contre la ligne de
    /// référence neutre dessinée devant, nommée dans la légende)
    /// et score GRI rapporté sur la même hauteur, gradué à droite de 0 à 100.
    private var graphique: some View {
        Chart {
            ForEach(synthese.semaines.filter { $0.indiceCharge != nil }) { point in
                BarMark(
                    x: .value("Semaine", point.debutSemaine, unit: .weekOfYear),
                    y: .value("Charge", point.indiceCharge ?? 0)
                )
                .foregroundStyle(teinteCharge.opacity(estAttenuee(point.debutSemaine) ? 0.2 : 0.6))
                .cornerRadius(3)
            }

            ForEach(synthese.semaines.filter { $0.score != nil }) { point in
                LineMark(
                    x: .value("Semaine", point.debutSemaine, unit: .weekOfYear),
                    y: .value("Score", (point.score ?? 0) / 100 * maxCharge)
                )
                .foregroundStyle(teinteScore)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            // Référence (indice 1) dessinée après les barres, en neutre :
            // en orange derrière elles, elle disparaissait.
            RuleMark(y: .value("Référence", 1.0))
                .foregroundStyle(Color.gray)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))

            if let semaineSelectionnee {
                RuleMark(x: .value("Semaine sélectionnée", semaineSelectionnee, unit: .weekOfYear))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: 0...maxCharge)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.caption2)
            }
        }
        .chartYAxis {
            // Seule échelle graduée : celle du score. La charge se lit par
            // rapport à la ligne de référence ; le % exact au tap.
            AxisMarks(position: .trailing, values: [0, maxCharge / 2, maxCharge]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int((v / maxCharge * 100).rounded()))")
                            .font(.caption2)
                            .foregroundStyle(teinteScore)
                    }
                }
            }
        }
        .chartXSelection(value: semaineSelectionneeBrute)
        // Bulle d'info au doigt, même patron que le graphique d'une nuit B1
        // (`CourbesNocturnesChart`) : posée en haut de la zone de tracé,
        // bornée pour ne pas en sortir, rien ne bouge autour.
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame,
                   let semaineSelectionnee,
                   let point = synthese.semaines.first(where: { $0.debutSemaine == semaineSelectionnee }),
                   let x = proxy.position(forX: semaineSelectionnee) {
                    let zone = geo[plotFrame]
                    let largeur = min(zone.width - 8, 240)
                    BulleSemaine(
                        debutSemaine: point.debutSemaine,
                        charge: point.indiceCharge.map { "Charge \(ecartFormate($0))" } ?? "Charge : pas assez de recul",
                        score: point.score.map { "GRI \(Int($0.rounded()))" },
                        reference: texteReference(semaine: point.debutSemaine),
                        teinteCharge: teinteCharge,
                        teinteScore: teinteScore
                    )
                    .frame(width: largeur)
                    .fixedSize(horizontal: false, vertical: true)
                    .position(
                        x: min(max(zone.minX + x, zone.minX + largeur / 2), zone.maxX - largeur / 2),
                        y: zone.minY + 36
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .frame(height: 220)
    }

    private var legendeCharge: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(teinteCharge.opacity(0.6)).frame(width: 8, height: 8)
            Text("Charge vs référence")
        }
        .fixedSize()
    }

    private var legendeScore: some View {
        HStack(spacing: 5) {
            Rectangle().fill(teinteScore).frame(width: 14, height: 2.5)
            Text("Score GRI")
        }
        .fixedSize()
    }

    private var legendeReference: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle().fill(Color.gray).frame(width: 4, height: 1.5)
                }
            }
            Text("Référence")
        }
        .fixedSize()
    }

    /// Mode d'emploi, replié par défaut (même patron que « Zones de la
    /// nuit » de B1) : utile une fois, encombrant ensuite.
    @State private var aideDepliee = false

    private var aideLecture: some View {
        DisclosureGroup(isExpanded: $aideDepliee) {
            contenuAide
                .padding(.top, 8)
        } label: {
            Text("Comment lire ce graphique")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var contenuAide: some View {
        VStack(alignment: .leading, spacing: 6) {
            ligneAide("Barre orange : votre charge de la semaine. À la hauteur de la ligne pointillée, semaine habituelle. Touchez une semaine pour l'écart en %.")
            ligneAide("Référence : votre moyenne des 4 semaines précédentes, hors semaine juste avant. Chaque semaine a donc la sienne : glissez le doigt sur le graphique pour la voir.")
            ligneAide("Pas de barre : moins de 5 semaines d'historique avant cette semaine, pas encore de comparaison possible.")
            ligneAide("Courbe bleue : score GRI moyen de la semaine, sur 100, échelle de droite.")
            if let chargeActive {
                ligneAide(TextesChargeActive.sources(chargeActive))
                ligneAide(TextesChargeActive.fcMax(chargeActive.fcMax))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func ligneAide(_ texte: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(texte).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `chartXSelection` retombe sur la date exacte du doigt, pas le début
    /// de semaine du point le plus proche — cette passerelle arrondit à la
    /// semaine avant d'écrire dans `semaineSelectionnee`.
    private var semaineSelectionneeBrute: Binding<Date?> {
        Binding(
            get: { semaineSelectionnee },
            set: { nouvelle in
                guard let nouvelle else { semaineSelectionnee = nil; return }
                semaineSelectionnee = synthese.semaines.min {
                    abs($0.debutSemaine.timeIntervalSince(nouvelle)) < abs($1.debutSemaine.timeIntervalSince(nouvelle))
                }?.debutSemaine
            }
        )
    }

    /// Référence **de la semaine touchée**, en faits : chaque barre a la
    /// sienne (ses 4 semaines précédentes, hors semaine juste avant), lue au
    /// même instant que son indice (fin de semaine, ou maintenant).
    private func texteReference(semaine debut: Date) -> String? {
        let fin = Calendar.current.date(byAdding: .day, value: 7, to: debut) ?? debut
        guard let r = ChargeActiveService.shared.contexte?.referenceEnFaits(a: min(fin, Date())) else { return nil }
        let seances = r.seancesParSemaine.formatted(.number.precision(.fractionLength(0...1)))
        var texte = "Référence : \(seances) séance\(r.seancesParSemaine >= 2 ? "s" : "") (\(DureeActivite.texte(r.minutesSeancesParSemaine)))"
        if r.minutesMarcheParSemaine >= 1 {
            texte += " + \(DureeActivite.texte(r.minutesMarcheParSemaine)) de marche"
        }
        return texte + " par semaine"
    }

    /// « +30 % » / « −15 % » par rapport à la référence — jamais le nombre brut.
    private func ecartFormate(_ indice: Double) -> String {
        let pct = Int(((indice - 1) * 100).rounded())
        if pct == 0 { return "comme la référence" }
        return "\(pct > 0 ? "+" : "\u{2212}")\(abs(pct)) %"
    }
}

// MARK: - Charge active

/// Provenance de la charge active, affichée dans le mode d'emploi du
/// graphique (l'ancienne carte « Charge active » est remplacée par la carte
/// de l'épisode en cours, C1 § 9).
private enum TextesChargeActive {

    /// Valeur de FC max qui pondère les séances, et son origine.
    static func fcMax(_ fcMax: FCMaxRetenue) -> String {
        let bpm = Int(fcMax.bpm.rounded())
        let seances = "\(fcMax.seancesAvecFC) séance\(fcMax.seancesAvecFC >= 2 ? "s" : "")"
        return switch fcMax.origine {
        case .observee:
            "Intensité des séances : FC moyenne rapportée à votre FC max observée, \(bpm) bpm (pic soutenu sur \(seances) des 12 derniers mois)."
        case .theorique:
            "Intensité des séances : FC moyenne rapportée à une FC max théorique de \(bpm) bpm. Valeur observée à partir de \(CalculFCMax.seancesMinimum) séances avec FC (\(seances) pour l'instant)."
        }
    }

    static func sources(_ synthese: SyntheseChargeActive) -> String {
        synthese.marcheIncluse
            ? "Charge : séances et marche soutenue, décroissance sur 24 h. Référence : 4 semaines, hors semaine en cours."
            : "Charge partielle : séances seules, pas non lus depuis Apple Santé."
    }
}

// MARK: - Bulle de la semaine

/// Bulle d'info affichée au doigt sur la chronologie — même traitement que
/// la bulle de valeur du graphique d'une nuit B1 (fond système, coins 12,
/// ombre légère).
private struct BulleSemaine: View {
    let debutSemaine: Date
    let charge: String
    let score: String?
    let reference: String?
    let teinteCharge: Color
    let teinteScore: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Semaine du \(debutSemaine.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))")
                .font(.caption.bold())
            HStack(spacing: 8) {
                Text(charge).foregroundStyle(teinteCharge)
                Text(score ?? "GRI indisponible").foregroundStyle(score == nil ? Color.secondary : teinteScore)
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            if let reference {
                Text(reference)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    NavigationStack {
        PageCorrelationChargeGlycemie(
            synthese: .mock,
            chargeActive: SyntheseChargeActive(
                etat: .disponible(indice: 1.32, niveau: .haute, depuisJours: 4),
                marcheIncluse: true,
                fcMax: FCMaxRetenue(bpm: 183, origine: .observee, seancesAvecFC: 42)
            )
        )
    }
}

#Preview("Charge active partielle") {
    NavigationStack {
        PageCorrelationChargeGlycemie(
            synthese: .mock,
            chargeActive: SyntheseChargeActive(etat: .pasAssezDeRecul, marcheIncluse: false)
        )
    }
}

#Preview("Sombre") {
    NavigationStack {
        PageCorrelationChargeGlycemie(synthese: .mock)
    }
    .preferredColorScheme(.dark)
}
#endif
