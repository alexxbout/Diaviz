//
//  PageBilanCorrections.swift
//  diaviz
//

import Charts
import SwiftUI

/// Page **« Corrections »** — bilan de toutes les corrections rapides
/// (`motif == .correction`), à toute heure de la journée. Même famille que
/// B1/B2+B3/R1 : purement rétrospective, factuelle, aucune dose suggérée.
///
/// Distincte de « Hypos au coucher » (B2+B3), qui ne regarde que les
/// corrections prises au coucher : ici, toutes les corrections comptent,
/// jour comme nuit.
///
/// Structure, espacée pour laisser chaque bloc respirer (40pt entre
/// sections, contre 24 en V1 — la densité initiale rendait la page dure à
/// scanner) :
///   1. Carte de métriques (grille 2×2 + répartition en anneau)
///   2. Segmentation dose vs ratio de correction (barres, si ratio configuré)
///   3. Liste des corrections (tri date/glycémie)
struct PageBilanCorrections: View {

    let bilan: BilanCorrections

    enum TriCorrections: CaseIterable {
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
    @State private var tri: TriCorrections = .date

    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            EnTeteAnalyse(
                surtitre: "Corrections",
                titre: "Bilan des corrections",
                accroche: "Ce que vos corrections d'insuline ont produit, à toute heure.",
                ambiance: .corrections
            )

            VStack(alignment: .leading, spacing: 12) {
                TitreSection(texte: "Vue d'ensemble")
                carteMetriques
            }

            if !bilan.buckets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    TitreSection(texte: "Dose vs résultat")
                    sectionBuckets
                }
            }

            if bilan.nombre > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    TitreSection(texte: "Corrections")
                    sectionListe
                }
            }
        }
    }

    // MARK: - 1. Carte de métriques

    @ViewBuilder
    private var carteMetriques: some View {
        if bilan.nombre == 0 {
            Text("Aucune correction analysable pour l'instant — il faut de la couverture CGM après vos corrections.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .surfaceCarte()
        } else {
            VStack(alignment: .leading, spacing: 24) {
                enTeteMetriques

                // Anneau + tuiles côte à côte hors accessibilité : l'anneau
                // porte la répartition d'un coup d'œil, les tuiles le détail
                // dangereux (hypos, rechutes). En taille de texte agrandie,
                // les deux s'empilent pour ne pas comprimer les libellés.
                if tailleTexte.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 24) {
                        anneauRepartition
                        tuiles
                    }
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        anneauRepartition
                            .frame(width: 130)
                        tuiles
                    }
                }

                if let moyen = bilan.iobMoyenAuxCorrections {
                    Divider()
                    ligneIOB(moyen: moyen, max: bilan.iobMaxAuxCorrections ?? moyen)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCarte()
        }
    }

    private var enTeteMetriques: some View {
        Text("\(bilan.nombre) correction\(bilan.nombre > 1 ? "s" : "") analysée\(bilan.nombre > 1 ? "s" : "")")
            .font(.headline)
            .monospacedDigit()
    }

    // MARK: Anneau de répartition (Charts)

    private struct PartRepartition: Identifiable {
        let id: IssueCorrection
        let libelle: String
        let valeur: Int
        let couleur: Color
    }

    private var repartition: [PartRepartition] {
        [
            PartRepartition(id: .adapte, libelle: "Adaptées", valeur: bilan.nombreAdapte, couleur: .green),
            PartRepartition(id: .insuffisant, libelle: "Insuffisantes", valeur: bilan.nombreInsuffisant, couleur: .orange),
            PartRepartition(id: .surCorrection, libelle: "Sur-corrections", valeur: bilan.nombreSurCorrection, couleur: .red),
        ]
        .filter { $0.valeur > 0 }
    }

    /// Anneau plutôt que camembert : le centre porte le taux d'adaptation en
    /// texte, l'information la plus dense de la carte — un simple camembert
    /// laisserait ce chiffre nulle part où se poser.
    private var anneauRepartition: some View {
        ZStack {
            Chart(repartition) { part in
                SectorMark(
                    angle: .value("Corrections", part.valeur),
                    innerRadius: .ratio(0.68),
                    angularInset: 1.5
                )
                .foregroundStyle(part.couleur)
                .cornerRadius(3)
            }
            .chartLegend(.hidden)

            VStack(spacing: 0) {
                Text(bilan.tauxAdapteFormate)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("adaptées")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
        .frame(height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            repartition.map { "\($0.libelle) : \($0.valeur)" }.joined(separator: ", ")
        )
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
                valeur: bilan.nombreHyposCausees,
                libelle: bilan.nombreHyposCausees > 1 ? "hypos causées" : "hypo causée",
                detail: nil,
                symbole: "arrow.down.right.circle.fill",
                couleur: .red
            ),
            Metrique(
                valeur: bilan.nombreRechutes,
                libelle: "avec rechute",
                detail: "resucrage puis nouvelle hypo",
                symbole: "arrow.uturn.down.circle.fill",
                couleur: .red
            ),
        ]
    }

    /// Empilées en colonne, à côté de l'anneau — deux tuiles seulement
    /// désormais (le taux global vit dans l'anneau, l'insuffisance dans la
    /// répartition), plus d'espace pour chacune.
    private var tuiles: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(metriques, id: \.libelle) { m in
                tuile(m)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tuile(_ m: Metrique) -> some View {
        let teinte: Color = m.valeur > 0 ? m.couleur : .secondary
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
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
            if let detail = m.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.valeur) \(m.libelle)\(m.detail.map { ", \($0)" } ?? "")")
    }

    private func ligneIOB(moyen: Double, max: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "syringe.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("IOB aux corrections : \(formateIOB(moyen))u en moyenne, \(formateIOB(max))u max")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func formateIOB(_ valeur: Double) -> String {
        String(format: "%.1f", valeur)
    }

    // MARK: - 2. Dose vs résultat (barres)

    /// Une barre horizontale par tranche — le taux se lit d'un coup d'œil,
    /// le dénominateur reste en toutes lettres sous la barre (jamais un
    /// pourcentage seul).
    private var sectionBuckets: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(bilan.buckets, id: \.tranche) { bucket in
                ligneBucket(bucket)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
    }

    private func ligneBucket(_ bucket: BucketDoseCorrection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.tranche.libelle)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(bucket.tauxAdapte, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            Chart {
                BarMark(x: .value("Taux", bucket.tauxAdapte))
                    .foregroundStyle(Color.green.gradient)
                    .cornerRadius(4)
            }
            .chartXScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(Color.secondary.opacity(0.12))
            }
            .frame(height: 10)

            Text("\(bucket.adaptees) adaptée\(bucket.adaptees > 1 ? "s" : "") sur \(bucket.total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 3. Liste des corrections

    private var correctionsTriees: [CorrectionEvaluee] {
        switch tri {
        case .date:     return bilan.corrections.sorted { $0.date > $1.date }
        case .glycemie: return bilan.corrections.sorted { $0.glycemie < $1.glycemie }
        }
    }

    private var sectionListe: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                menuTri
            }
            VStack(spacing: 12) {
                ForEach(correctionsTriees) { correction in
                    ligneCorrection(correction)
                }
            }
        }
    }

    private var menuTri: some View {
        Menu {
            Picker("Trier par", selection: $tri) {
                ForEach(TriCorrections.allCases, id: \.self) { valeur in
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
        .accessibilityLabel("Trier les corrections")
    }

    private func ligneCorrection(_ c: CorrectionEvaluee) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: c.issue.symbole)
                .font(.title3)
                .foregroundStyle(c.issue.couleur)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(c.glycemie) mg/dL · \(formateDose(c.dose))u")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                Text(sousLigne(c))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(c.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(16)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
    }

    /// « Pic 245 · IOB 0,8u · rechute » — tout ce qui n'est pas déjà en tête
    /// de ligne, dans l'ordre pic → IOB → rechute.
    private func sousLigne(_ c: CorrectionEvaluee) -> String {
        var parts = [c.issue.libelle, "pic \(c.picMax)"]
        if let iob = c.iobAvant { parts.append("IOB \(formateIOB(iob))u") }
        if c.hypoCausee, let iobHypo = c.iobAuMomentHypo {
            parts.append("IOB à l'hypo \(formateIOB(iobHypo))u")
        }
        if c.rechute { parts.append("rechute") }
        return parts.joined(separator: " · ")
    }

    private func formateDose(_ valeur: Double) -> String {
        valeur == floor(valeur) ? String(format: "%.0f", valeur) : String(format: "%.1f", valeur)
    }
}

// MARK: - Taux formaté (arrondi, pour le centre de l'anneau)

private extension BilanCorrections {
    var tauxAdapteFormate: String {
        guard nombre > 0 else { return "—" }
        let taux = Double(nombreAdapte) / Double(nombre)
        return taux.formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Habillage de l'issue

private extension IssueCorrection {
    var libelle: String {
        switch self {
        case .insuffisant:   return "insuffisante"
        case .adapte:        return "adaptée"
        case .surCorrection: return "sur-correction"
        }
    }

    var symbole: String {
        switch self {
        case .insuffisant:   return "arrow.up.right.circle.fill"
        case .adapte:        return "checkmark.circle.fill"
        case .surCorrection: return "arrow.down.right.circle.fill"
        }
    }

    var couleur: Color {
        switch self {
        case .insuffisant:   return .orange
        case .adapte:        return .green
        case .surCorrection: return .red
        }
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Corrections — mock") {
    ScrollView {
        PageBilanCorrections(bilan: .mock)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Corrections — vide") {
    ScrollView {
        PageBilanCorrections(bilan: .vide)
            .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
