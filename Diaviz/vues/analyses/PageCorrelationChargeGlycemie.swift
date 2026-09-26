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
                    accroche: "Votre charge d'activité comparée à votre référence, et votre score glycémique, semaine après semaine.",
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

    // MARK: - Chronologie

    /// Haut de l'échelle de charge : marge au-dessus de la plus haute barre
    /// (place pour son %), et jamais moins de 1,5 pour que la ligne de
    /// référence (1) ne colle pas au sommet.
    private var maxCharge: Double {
        max((synthese.semaines.compactMap(\.indiceCharge).max() ?? 0) * 1.2, 1.5)
    }

    /// Même domaine horizontal pour les deux graphiques : les colonnes des
    /// semaines tombent exactement l'une sous l'autre.
    private var domaineSemaines: ClosedRange<Date> {
        let debut = synthese.semaines.first?.debutSemaine ?? Date()
        let fin = synthese.semaines.last.flatMap {
            Calendar.current.date(byAdding: .day, value: 7, to: $0.debutSemaine)
        } ?? debut
        return debut...max(fin, debut)
    }

    private func estAttenuee(_ semaine: Date) -> Bool {
        semaineSelectionnee != nil && semaineSelectionnee != semaine
    }

    private var chronologie: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chronologie")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            // Ligne de détail de la semaine tappée, hauteur fixe pour ne pas
            // faire sauter la mise en page.
            detailSelection
                .frame(height: 16)

            Text("Charge par rapport à votre référence")
                .font(.caption.bold())
                .foregroundStyle(teinteCharge)
            graphiqueCharge

            Text("Score GRI moyen (sur 100)")
                .font(.caption.bold())
                .foregroundStyle(teinteScore)
                .padding(.top, 4)
            graphiqueScore

            aideLecture
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    private var graphiqueCharge: some View {
        Chart {
            ForEach(synthese.semaines.filter { $0.indiceCharge != nil }) { point in
                BarMark(
                    x: .value("Semaine", point.debutSemaine, unit: .weekOfYear),
                    y: .value("Charge", point.indiceCharge ?? 0)
                )
                .foregroundStyle(teinteCharge.opacity(estAttenuee(point.debutSemaine) ? 0.2 : 0.6))
                .cornerRadius(3)
                .annotation(position: .top, spacing: 2) {
                    Text(ecartFormate(point.indiceCharge ?? 1))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }

            // Référence (indice 1) dessinée **après** les barres, en neutre :
            // en orange derrière elles, elle disparaissait.
            RuleMark(y: .value("Référence", 1.0))
                .foregroundStyle(Color.primary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("référence")
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                }

            if let semaineSelectionnee {
                RuleMark(x: .value("Semaine sélectionnée", semaineSelectionnee, unit: .weekOfYear))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: domaineSemaines)
        .chartYScale(domain: 0...maxCharge)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXSelection(value: semaineSelectionneeBrute)
        .frame(height: 150)
    }

    private var graphiqueScore: some View {
        Chart {
            ForEach(synthese.semaines.filter { $0.score != nil }) { point in
                LineMark(
                    x: .value("Semaine", point.debutSemaine, unit: .weekOfYear),
                    y: .value("Score", point.score ?? 0)
                )
                .foregroundStyle(teinteScore)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Semaine", point.debutSemaine, unit: .weekOfYear),
                    y: .value("Score", point.score ?? 0)
                )
                .foregroundStyle(teinteScore.opacity(estAttenuee(point.debutSemaine) ? 0.3 : 1))
                .symbolSize(20)
            }

            if let semaineSelectionnee {
                RuleMark(x: .value("Semaine sélectionnée", semaineSelectionnee, unit: .weekOfYear))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: domaineSemaines)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                AxisGridLine()
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXSelection(value: semaineSelectionneeBrute)
        .frame(height: 110)
    }

    /// Mode d'emploi court, toujours visible.
    private var aideLecture: some View {
        VStack(alignment: .leading, spacing: 6) {
            ligneAide("Barre orange : votre charge de la semaine. À la hauteur de la ligne « référence », semaine habituelle. Le % au-dessus dit l'écart.")
            ligneAide("Référence : votre moyenne des 4 semaines précédentes, hors semaine juste avant.")
            ligneAide("Pas de barre : moins de 5 semaines d'historique avant cette semaine, pas encore de comparaison possible.")
            ligneAide("En dessous : score GRI moyen de la semaine, sur 100, pour les mêmes semaines.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
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

    @ViewBuilder
    private var detailSelection: some View {
        if let semaineSelectionnee, let point = synthese.semaines.first(where: { $0.debutSemaine == semaineSelectionnee }) {
            HStack(spacing: 10) {
                Text(semaineSelectionnee.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .font(.caption.bold())
                Text(point.indiceCharge.map { "charge \(ecartFormate($0))" } ?? "pas assez de recul")
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

    /// « +30 % » / « −15 % » par rapport à la normale — jamais le nombre brut.
    private func ecartFormate(_ indice: Double) -> String {
        let pct = Int(((indice - 1) * 100).rounded())
        if pct == 0 { return "comme la référence" }
        return "\(pct > 0 ? "+" : "\u{2212}")\(abs(pct)) %"
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
            Text("Dérive basale selon la charge active du jour")
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

            Text("Barres centrées sur 0 : à droite, basale trop faible ; à gauche, trop forte.")
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
            Text("Il faut au moins 5 semaines d'historique d'activité pour établir votre référence.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .aucuneActiviteDeReference:
            Text("Pas de référence")
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
        if ecart == 0 { return "Au niveau de votre référence aujourd'hui" }
        let signe = ecart > 0 ? "+" : "\u{2212}"
        return "\(signe)\(abs(ecart)) % par rapport à votre référence aujourd'hui"
    }

    private func texteSources(_ synthese: SyntheseChargeActive) -> String {
        synthese.marcheIncluse
            ? "Moyenne de la journée. Séances et marche soutenue, décroissance sur 24 h. Référence : 4 semaines, hors semaine en cours."
            : "Partiel : séances seules, pas non lus depuis Apple Santé."
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
