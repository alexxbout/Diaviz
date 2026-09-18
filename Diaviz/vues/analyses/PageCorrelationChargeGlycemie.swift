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

    private let teinteCharge = Color.orange
    private let teinteTIR = Color.blue

    /// Semaine sélectionnée au tap/drag sur la chronologie — `nil` par
    /// défaut, la carte n'affiche alors rien de plus que le graphique.
    @State private var semaineSelectionnee: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnTeteAnalyse(
                    surtitre: "Sport",
                    titre: "Charge et glycémie",
                    accroche: "Votre charge d'activité et votre temps dans la cible, semaine après semaine — avec vos changements de dose de lente en repère.",
                    ambiance: .chargeActivite
                )
                chronologie
                if !synthese.changementsDose.isEmpty {
                    changementsDoseListe
                }
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
        max(synthese.semaines.map(\.charge).max() ?? 0, 1)
    }

    private var chronologie: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chronologie")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                legendePastille(couleur: teinteCharge.opacity(0.55), texte: "Charge", forme: .carre)
                legendePastille(couleur: teinteTIR, texte: "TIR", forme: .trait)
                legendePastille(couleur: .secondary, texte: "Δ dose", forme: .pointille)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Ligne de détail de la semaine tappée — remplace la légende
            // visuellement à la même hauteur pour ne pas faire sauter la
            // mise en page du reste de la carte.
            detailSelection
                .frame(height: 16)

            Chart {
                ForEach(synthese.semaines) { point in
                    BarMark(
                        x: .value("Semaine", point.debutSemaine, unit: .weekOfYear),
                        y: .value("Charge", point.charge)
                    )
                    .foregroundStyle(
                        (semaineSelectionnee == nil || semaineSelectionnee == point.debutSemaine)
                            ? teinteCharge.opacity(0.55) : teinteCharge.opacity(0.2)
                    )
                    .cornerRadius(3)
                }

                ForEach(synthese.semaines.filter { $0.tir != nil }) { point in
                    LineMark(
                        x: .value("Semaine", point.debutSemaine, unit: .weekOfYear),
                        y: .value("TIR", (point.tir ?? 0) / 100 * maxCharge)
                    )
                    .foregroundStyle(teinteTIR)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

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
                AxisMarks(position: .leading)
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
                Text("charge \(Int(point.charge.rounded()))")
                    .font(.caption)
                    .foregroundStyle(teinteCharge)
                if let tir = point.tir {
                    Text("TIR \(Int(tir.rounded()))%")
                        .font(.caption)
                        .foregroundStyle(teinteTIR)
                } else {
                    Text("TIR indisponible")
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

    private enum FormeLegende { case carre, trait, pointille }

    private func legendePastille(couleur: Color, texte: String, forme: FormeLegende) -> some View {
        HStack(spacing: 5) {
            switch forme {
            case .carre:
                RoundedRectangle(cornerRadius: 2).fill(couleur).frame(width: 8, height: 8)
            case .trait:
                Rectangle().fill(couleur).frame(width: 14, height: 2.5)
            case .pointille:
                Rectangle().fill(couleur).frame(width: 1.5, height: 10)
            }
            Text(texte)
        }
    }

    private func doseFormatee(_ dose: Double) -> String {
        dose == dose.rounded() ? "\(Int(dose))u" : String(format: "%.1fu", dose)
    }

    // MARK: - Liste des changements de dose

    private var changementsDoseListe: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Changements de dose de lente")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(synthese.changementsDose.enumerated()), id: \.element.id) { index, marqueur in
                    if index > 0 { Divider() }
                    HStack {
                        Image(systemName: "syringe.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(marqueur.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(doseFormatee(marqueur.dose))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: NiveauCarte.carte.forme)
    }

    // MARK: - TIR par tranche de charge

    private var tranches: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Temps dans la cible selon votre charge")
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
                        Text("(n=\(tranche.nombreSemaines))")
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
            Text("Dérive moyenne de la nuit profonde (B1), nuits groupées par charge de leur semaine")
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

    private func couleurNiveau(_ niveau: NiveauChargeCorrelation) -> Color {
        switch niveau {
        case .basse:   return .red
        case .haute:   return .blue
        case .normale: return .secondary
        }
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    NavigationStack {
        PageCorrelationChargeGlycemie(synthese: .mock)
    }
}

#Preview("Sombre") {
    NavigationStack {
        PageCorrelationChargeGlycemie(synthese: .mock)
    }
    .preferredColorScheme(.dark)
}
#endif
