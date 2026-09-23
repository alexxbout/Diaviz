//
//  PageCorrelationChargeGlycemie.swift
//  diaviz
//

import Charts
import SwiftUI

/// Page d'analyse « Charge et équilibre glycémique » — corrèle la charge
/// d'activité continue, le temps dans la cible et la dérive basale moyenne
/// (B1, nuit profonde) sur `CalculCorrelationChargeTIR.nombreSemaines`
/// semaines, avec les changements de dose de lente comme repères temporels.
///
/// **Co-occurrence affichée, jamais une cause affirmée** — même garde-fou
/// que partout ailleurs dans l'app (B2/B3 pour sport/glucides, etc.).
/// Aucun seuil minimal n'empêche l'affichage d'une tranche : le nombre de
/// semaines/nuits (`n=`) reste toujours visible à côté du chiffre, c'est lui
/// qui porte l'honnêteté de la mesure.
struct PageCorrelationChargeGlycemie: View {

    let synthese: SyntheseCorrelationChargeTIR
    /// Charge active (`CalculChargeActive`) — `nil` tant que le premier
    /// calcul n'a pas abouti (lecture Apple Santé en cours).
    var chargeActive: SyntheseChargeActive? = nil

    private let teinteCharge = Color.orange
    private let teinteScore = Color.blue

    /// Semaine sélectionnée au tap/drag sur la chronologie — `nil` par
    /// défaut, la carte n'affiche alors rien de plus que le graphique.
    @State private var semaineSelectionnee: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnTeteAnalyse(
                    surtitre: "Sport",
                    titre: "Charge et glycémie",
                    accroche: "Votre charge active (séances et marche, relative à votre normale) et votre score glycémique, semaine après semaine — avec vos changements de dose de lente en repère.",
                    ambiance: .chargeActivite
                )
                CarteChargeActiveIndice(synthese: chargeActive)
                chronologie
                tranches
                if synthese.tranchesDerive.contains(where: { $0.deriveMoyenne != nil }) {
                    tranchesDerive
                }
                Label(
                    "Co-occurrence affichée, jamais une cause. \(CalculCorrelationChargeTIR.nombreSemaines) dernières semaines glissantes.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Charge et glycémie")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Chronologie superposée

    private var maxCharge: Double {
        max(synthese.semaines.compactMap(\.indiceCharge).max() ?? 0, 1.5)
    }

    private var chronologie: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chronologie")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                legendePastille(couleur: teinteCharge.opacity(0.55), texte: "Charge active / normale", forme: .carre)
                legendePastille(couleur: teinteScore, texte: "Score", forme: .trait)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                legendePastille(couleur: .secondary, texte: texteLegendeDose, forme: .pointille)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Ligne de détail de la semaine tappée — remplace la légende
            // visuellement à la même hauteur pour ne pas faire sauter la
            // mise en page du reste de la carte.
            detailSelection
                .frame(height: 16)

            Chart {
                ForEach(synthese.semaines.filter { $0.indiceCharge != nil }) { point in
                    BarMark(
                        x: .value("Semaine", point.debutSemaine, unit: .weekOfYear),
                        y: .value("Charge", point.indiceCharge ?? 0)
                    )
                    .foregroundStyle(
                        (semaineSelectionnee == nil || semaineSelectionnee == point.debutSemaine)
                            ? teinteCharge.opacity(0.55) : teinteCharge.opacity(0.2)
                    )
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

                // Repère de la normale personnelle (indice 1).
                RuleMark(y: .value("Normale", 1.0))
                    .foregroundStyle(teinteCharge.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // Repères de changement de dose — trait pointillé seul, sans
                // texte sur le graphique : avec plusieurs changements
                // rapprochés, les annotations se chevauchaient et devenaient
                // illisibles. Le détail (date + dose) vit dans la liste
                // `changementsDoseListe` juste en dessous.
                ForEach(synthese.changementsDose) { marqueur in
                    RuleMark(x: .value("Changement de dose", marqueur.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                if let semaineSelectionnee {
                    RuleMark(x: .value("Semaine sélectionnée", semaineSelectionnee, unit: .weekOfYear))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v == 1 ? "normale" : "0")
                                .font(.caption2)
                        }
                    }
                }
                AxisMarks(position: .trailing, values: [0, maxCharge / 2, maxCharge]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int((v / maxCharge * 100).rounded()))%")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXSelection(value: semaineSelectionneeBrute)
            .frame(height: 200)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
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

    @ViewBuilder
    private var detailSelection: some View {
        if let semaineSelectionnee, let point = synthese.semaines.first(where: { $0.debutSemaine == semaineSelectionnee }) {
            HStack(spacing: 10) {
                Text(semaineSelectionnee.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .font(.caption.bold())
                Text(point.indiceCharge.map { "charge \(ecartFormate($0))" } ?? "charge indisponible")
                    .font(.caption)
                    .foregroundStyle(teinteCharge)
                if let score = point.score {
                    Text("score \(Int(score.rounded()))")
                        .font(.caption)
                        .foregroundStyle(teinteScore)
                } else {
                    Text("score indisponible")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    self.semaineSelectionnee = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Color.clear
        }
    }

    private enum FormeLegende { case carre, trait, traitPointille, pointille }

    private func legendePastille(couleur: Color, texte: String, forme: FormeLegende) -> some View {
        HStack(spacing: 5) {
            switch forme {
            case .carre:
                RoundedRectangle(cornerRadius: 2).fill(couleur).frame(width: 8, height: 8)
            case .trait:
                Rectangle().fill(couleur).frame(width: 14, height: 2.5)
            case .traitPointille:
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(couleur).frame(width: 3, height: 2.5)
                    }
                }
            case .pointille:
                Rectangle().fill(couleur).frame(width: 1.5, height: 10)
            }
            Text(texte)
        }
    }

    /// « +30 % » / « −15 % » par rapport à la normale — jamais le nombre brut.
    private func ecartFormate(_ indice: Double) -> String {
        let pct = Int(((indice - 1) * 100).rounded())
        if pct == 0 { return "normale" }
        return "\(pct > 0 ? "+" : "\u{2212}")\(abs(pct)) %"
    }

    private func doseFormatee(_ dose: Double) -> String {
        dose == dose.rounded() ? "\(Int(dose))u" : String(format: "%.1fu", dose)
    }

    /// Légende du repère pointillé — dose courante par défaut, ou dose
    /// active pendant la semaine tappée sur le graphique (dernier changement
    /// à date ≤ début de cette semaine) : la légende suit le doigt au lieu
    /// de rester figée sur la dernière valeur connue.
    private var texteLegendeDose: String {
        if let semaineSelectionnee {
            guard let actif = synthese.changementsDose.last(where: { $0.date <= semaineSelectionnee }) else {
                return "Δ dose"
            }
            return "Δ dose (\(doseFormatee(actif.dose)))"
        }
        guard let dernier = synthese.changementsDose.last else { return "Δ dose" }
        return "Δ dose (\(doseFormatee(dernier.dose)))"
    }

    // MARK: - TIR par tranche de charge

    private var tranches: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Temps dans la cible selon la charge active du jour")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(synthese.tranches) { tranche in
                    ligneTranche(tranche)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private func ligneTranche(_ tranche: TrancheChargeTIR) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tranche.niveau.libelle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                if let tir = tranche.tirMoyen {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(tir.rounded()))%")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        Text("(n=\(tranche.nombreJours) j)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("aucune donnée")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill))
                    if let tir = tranche.tirMoyen {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(couleurNiveau(tranche.niveau))
                            .frame(width: geo.size.width * max(0.02, tir / 100))
                    }
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Dérive basale par tranche de charge (bloc 3)

    private var tranchesDerive: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dérive basale selon votre charge")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Text("Dérive moyenne de la nuit profonde (B1), nuits groupées par charge active du jour")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 14) {
                ForEach(synthese.tranchesDerive) { tranche in
                    ligneDerive(tranche)
                }
            }

            Text("Barres centrées sur 0 — à droite = basale trop faible, à gauche = trop forte.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private var maxDeriveAbsolue: Double {
        max(synthese.tranchesDerive.compactMap { $0.deriveMoyenne.map(abs) }.max() ?? 0, 1)
    }

    private func ligneDerive(_ tranche: TrancheDeriveBasale) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tranche.niveau.libelle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                if let derive = tranche.deriveMoyenne {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(deriveFormatee(derive))
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        Text("(n=\(tranche.nombreNuits) nuits)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("aucune donnée")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                let centre = geo.size.width / 2
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill))
                    Rectangle().fill(Color(.separator)).frame(width: 1).position(x: centre, y: 4)
                    if let derive = tranche.deriveMoyenne {
                        let largeur = min(centre, centre * abs(derive) / maxDeriveAbsolue)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(couleurNiveau(tranche.niveau))
                            .frame(width: max(2, largeur))
                            .position(x: derive >= 0 ? centre + largeur / 2 : centre - largeur / 2, y: 4)
                    }
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private func deriveFormatee(_ derive: Double) -> String {
        let signe = derive > 0 ? "+" : (derive < 0 ? "\u{2212}" : "")
        return "\(signe)\(Int(abs(derive).rounded())) mg/dL"
    }

    private func couleurNiveau(_ niveau: NiveauChargeActive) -> Color {
        niveau.couleur
    }
}

// MARK: - Charge active

/// Indice de charge active et niveau (bande d'hystérésis) — **jamais le
/// nombre brut**, toujours relatif à la normale personnelle. Affichage
/// volontairement minimal : phase de confrontation au ressenti avant la
/// frise des périodes (C1).
private struct CarteChargeActiveIndice: View {

    let synthese: SyntheseChargeActive?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Charge active")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if let synthese {
                contenu(synthese)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Lecture d'Apple Santé…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func contenu(_ synthese: SyntheseChargeActive) -> some View {
        switch synthese.etat {
        case .pasAssezDeRecul:
            Text("Pas assez de recul")
                .font(.title3.bold())
            Text("Il faut au moins 5 semaines d'historique d'activité pour établir votre normale.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .aucuneActiviteDeReference:
            Text("Pas de normale")
                .font(.title3.bold())
            Text("Aucune séance ni marche soutenue sur les 4 semaines de référence : pas d'indice à calculer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .disponible(indice, niveau, depuisJours):
            HStack(alignment: .firstTextBaseline) {
                Text(niveau.libelle)
                    .font(.title3.bold())
                    .foregroundStyle(couleur(niveau))
                Spacer(minLength: 8)
                if let depuisJours {
                    Text("depuis \(depuisJours) j")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(texteIndice(indice))
                .font(.subheadline)
                .monospacedDigit()
        }
        Text(texteSources(synthese))
            .font(.caption)
            .foregroundStyle(synthese.marcheIncluse ? Color.secondary : Color.orange)
    }

    private func texteIndice(_ indice: Double) -> String {
        let ecart = Int(((indice - 1) * 100).rounded())
        if ecart == 0 { return "Au niveau de votre normale" }
        let signe = ecart > 0 ? "+" : "\u{2212}"
        return "\(signe)\(abs(ecart)) % par rapport à votre normale"
    }

    private func texteSources(_ synthese: SyntheseChargeActive) -> String {
        synthese.marcheIncluse
            ? "Séances et marche soutenue, décroissance sur 24 h. Normale : 4 semaines, hors semaine en cours."
            : "Partiel : séances seules — pas non lus depuis Apple Santé."
    }

    private func couleur(_ niveau: NiveauChargeActive) -> Color {
        switch niveau {
        case .basse:   .red
        case .haute:   .blue
        case .normale: .primary
        }
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
                marcheIncluse: true
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
