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
/// **Deux portées séparées** (`Portee`) : une correction prise à moins de la
/// fenêtre réglée (Profil → Ratios → Corrections, 30 min par défaut) d'un
/// repas voit sa courbe CGM portée par les glucides autant que par
/// l'insuline — la mélanger aux corrections isolées fausserait le taux
/// d'adaptation. Le picker segmenté bascule entre les deux, jamais affichées
/// ensemble.
///
/// Par portée sélectionnée, deux blocs (40pt entre sections pour respirer) :
///   1. Carte de métriques (répartition en anneau + tuiles dangereuses)
///   2. Segmentation dose vs ratio de correction (si ratio configuré)
///
/// La liste correction par correction a été retirée : sans détail de
/// soirée à ouvrir (contrairement à `PageHyposCoucher`), elle n'ajoutait
/// qu'une redite tassée des mêmes chiffres déjà agrégés au-dessus.
struct PageBilanCorrections: View {

    let bilan: BilanCorrections

    private enum Portee: CaseIterable {
        case isolees, auRepas

        var libelle: String {
            switch self {
            case .isolees: return "Isolées"
            case .auRepas: return "Au repas"
            }
        }
    }

    /// Défaut sur la portée la mieux dotée — pas de préférence a priori
    /// entre les deux, mais ouvrir sur une portée vide serait déroutant.
    @State private var portee: Portee

    init(bilan: BilanCorrections) {
        self.bilan = bilan
        _portee = State(initialValue: bilan.auRepas.nombre > bilan.isolees.nombre ? .auRepas : .isolees)
    }

    private var sousBilan: SousBilanCorrections {
        portee == .isolees ? bilan.isolees : bilan.auRepas
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            EnTeteAnalyse(
                surtitre: "Corrections",
                titre: "Bilan des corrections",
                accroche: "Ce que vos corrections d'insuline ont produit, à toute heure.",
                ambiance: .corrections
            )

            if bilan.nombreTotal > 0 {
                Picker("Portée", selection: $portee) {
                    ForEach(Portee.allCases, id: \.self) { p in
                        Text(p.libelle).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            SousPageBilanCorrections(sousBilan: sousBilan)
        }
    }
}

// MARK: - Contenu d'une portée

/// Le contenu affiché pour une portée (isolées ou au repas) — extrait pour
/// que `PageBilanCorrections` ne porte que le picker et la sélection.
private struct SousPageBilanCorrections: View {

    let sousBilan: SousBilanCorrections

    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                TitreSection(texte: "Vue d'ensemble")
                carteMetriques
            }

            if !sousBilan.buckets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    TitreSection(texte: "Dose vs résultat")
                    sectionBuckets
                }
            }
        }
    }

    // MARK: - 1. Carte de métriques

    @ViewBuilder
    private var carteMetriques: some View {
        if sousBilan.nombre == 0 {
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

                if let moyen = sousBilan.iobMoyenAuxCorrections {
                    Divider()
                    ligneIOB(moyen: moyen, max: sousBilan.iobMaxAuxCorrections ?? moyen)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCarte()
        }
    }

    private var enTeteMetriques: some View {
        Text("\(sousBilan.nombre) correction\(sousBilan.nombre > 1 ? "s" : "") analysée\(sousBilan.nombre > 1 ? "s" : "")")
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
            PartRepartition(id: .adapte, libelle: "Adaptées", valeur: sousBilan.nombreAdapte, couleur: .green),
            PartRepartition(id: .insuffisant, libelle: "Insuffisantes", valeur: sousBilan.nombreInsuffisant, couleur: .orange),
            PartRepartition(id: .surCorrection, libelle: "Sur-corrections", valeur: sousBilan.nombreSurCorrection, couleur: .red),
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
                Text(sousBilan.tauxAdapteFormate)
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
                valeur: sousBilan.nombreHyposCausees,
                libelle: sousBilan.nombreHyposCausees > 1 ? "hypos causées" : "hypo causée",
                detail: nil,
                symbole: "arrow.down.right.circle.fill",
                couleur: .red
            ),
            Metrique(
                valeur: sousBilan.nombreRechutes,
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
    /// pourcentage seul). Trait plein sans dégradé ni fond : la carte
    /// « Vue d'ensemble » porte déjà la couleur au-dessus, ces barres n'ont
    /// besoin que d'un repère de longueur.
    private var sectionBuckets: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(sousBilan.buckets, id: \.tranche) { bucket in
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

            // Capsule pleine plutôt qu'un `Chart` : une seule valeur à
            // représenter, pas besoin du poids d'un graphique pour ça.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * bucket.tauxAdapte)
                }
            }
            .frame(height: 6)

            Text("\(bucket.adaptees) adaptée\(bucket.adaptees > 1 ? "s" : "") sur \(bucket.total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Taux formaté (arrondi, pour le centre de l'anneau)

private extension SousBilanCorrections {
    var tauxAdapteFormate: String {
        guard nombre > 0 else { return "—" }
        let taux = Double(nombreAdapte) / Double(nombre)
        return taux.formatted(.percent.precision(.fractionLength(0)))
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
