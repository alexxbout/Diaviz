//
//  SheetGuideTendanceBasale.swift
//  diaviz
//

import SwiftUI
import Charts

/// Guide de lecture de l'analyse « Tendance basale » (B1) — ouvert depuis le
/// bouton en pied de la page.
///
/// Volontairement **hors de la Bibliothèque** : celle-ci porte des faits de la
/// littérature, jamais du comportement applicatif. Ici on explique ce que
/// *cette app* calcule, avec des courbes d'exemple fabriquées — aucune donnée
/// personnelle n'est lue.
///
/// Trois sections : ce que l'analyse regarde, les verdicts possibles avec leur
/// courbe type, et ce qu'elle ne peut pas dire.
struct SheetGuideTendanceBasale: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionPrincipe
                    sectionVerdicts
                    sectionExclusions
                    sectionLimites
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Comment lire cette analyse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Principe

    private var sectionPrincipe: some View {
        carte {
            Text("Ce que l'analyse regarde")
                .font(.headline)

            Text("""
            La basale ne se lit que sur la partie de la nuit où **rien d'autre \
            n'agit** : plus de repas en cours de digestion, plus d'insuline \
            rapide active, pas encore de montée d'aube. Cette fenêtre est \
            appelée la **nuit profonde** — elle démarre 2 h après votre lente et \
            s'arrête à 4 h du matin.
            """)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            CourbeGuide(
                points: CourbeGuide.stable,
                zoneAnalysee: 0.45...0.8,
                teinte: .green
            )

            Text("La zone teintée est la seule mesurée. Le reste de la nuit est affiché comme contexte.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Verdicts

    private var sectionVerdicts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Les verdicts possibles")
                .font(.headline)
                .padding(.horizontal, 4)

            Text("""
            Le verdict porte sur la **dérive** : de combien la glycémie a bougé \
            entre le début et la fin de la nuit profonde. Le seuil est ±30 mg/dL, \
            la règle de référence pour tester une basale à jeun.
            """)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            ForEach(CasVerdict.tous) { cas in
                carte {
                    HStack(spacing: 8) {
                        Image(systemName: cas.icone)
                            .font(.footnote.weight(.semibold))
                        Text(cas.titre)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(cas.couleur)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(cas.couleur.opacity(0.13), in: Capsule())

                    CourbeGuide(points: cas.points, zoneAnalysee: 0.45...0.8, teinte: cas.couleur)

                    Text(cas.explication)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Exclusions

    private var sectionExclusions: some View {
        carte {
            Text("Pourquoi une nuit est écartée")
                .font(.headline)

            Text("""
            Une nuit dont la glycémie bouge pour une autre raison que la basale \
            ne dit rien de la basale. Plutôt que d'en tirer un verdict faux, \
            l'analyse l'écarte et affiche le motif. Ces nuits ne sont pas \
            perdues : elles restent visibles dans « Hypos au coucher ».
            """)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(MotifGuide.tous) { motif in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: motif.icone)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(motif.titre)
                                .font(.subheadline.weight(.medium))
                            Text(motif.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Limites

    private var sectionLimites: some View {
        carte {
            Text("Ce que cette analyse ne dit pas")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ligneLimite("Elle ne propose jamais de dose. Elle décrit ce qui s'est passé — la décision vous appartient, avec votre médecin.")
                ligneLimite("Elle ne juge pas une nuit isolée. Le verdict porte sur les 5 dernières nuits exploitables, jamais sur une seule.")
                ligneLimite("Elle ne dit rien de l'endormissement ni des corrections du soir : c'est le sujet de « Hypos au coucher ».")
                ligneLimite("Elle n'explique pas pourquoi une nuit dérive. Elle constate la dérive et exclut les causes qu'elle sait identifier.")
            }
        }
    }

    private func ligneLimite(_ texte: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(.tertiary)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(texte)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Habillage

    @ViewBuilder
    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            contenu()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }
}

// MARK: - Cas de verdict

private struct CasVerdict: Identifiable {
    let id = UUID()
    let titre: String
    let icone: String
    let couleur: Color
    let points: [Double]
    let explication: String

    static let tous: [CasVerdict] = [
        CasVerdict(
            titre: "Stable",
            icone: "checkmark.circle.fill",
            couleur: .green,
            points: CourbeGuide.stable,
            explication: "La glycémie bouge de moins de 30 mg/dL sur la nuit profonde. Rien à signaler du côté de la basale."
        ),
        CasVerdict(
            titre: "Tendance basse",
            icone: "arrow.down.right",
            couleur: .red,
            points: CourbeGuide.descendante,
            explication: "La glycémie perd plus de 30 mg/dL en approchant de l'hypo, sans que rien ne l'explique. Une hypo d'au moins 15 minutes suffit aussi, même si la courbe paraît plate : la stabilité venait alors du resucrage. Un passage plus bref sous 70 ne compte pas."
        ),
        CasVerdict(
            titre: "Tendance haute",
            icone: "arrow.up.right",
            couleur: .orange,
            points: CourbeGuide.ascendante,
            explication: "La glycémie gagne plus de 30 mg/dL en approchant de l'hyper, alors que la digestion est finie et qu'aucune insuline rapide n'agit encore. Une hyper sans repas pour l'expliquer suffit aussi, même corrigée."
        ),
        CasVerdict(
            titre: "En amélioration",
            icone: "trending.up",
            couleur: .green,
            points: CourbeGuide.amelioration,
            explication: "Les nuits d'avant penchaient d'un côté, les dernières reviennent vers la cible. Évite qu'une alerte reste figée après que la situation s'est réglée d'elle-même — reprise du sport, par exemple."
        )
    ]
}

// MARK: - Motifs d'exclusion

private struct MotifGuide: Identifiable {
    let id = UUID()
    let titre: String
    let detail: String
    let icone: String

    static let tous: [MotifGuide] = [
        MotifGuide(titre: "Correction au coucher",
                   detail: "Une rapide a été prise dans la fenêtre — c'est elle qui fait descendre, pas la basale.",
                   icone: "syringe"),
        MotifGuide(titre: "IOB résiduel",
                   detail: "Une rapide plus ancienne agit encore au début de la nuit profonde.",
                   icone: "drop.fill"),
        MotifGuide(titre: "Repas tardif copieux",
                   detail: "Un dîner très glucidique s'assimile tard : la glycémie monte en pleine nuit. Le seuil est réglable dans Profil.",
                   icone: "fork.knife"),
        MotifGuide(titre: "Rebond post-hypo",
                   detail: "Après une remontée, la glycémie redescend de son dépassement. Pente réelle, mais qui ne vient pas de la basale.",
                   icone: "arrow.uturn.down"),
        MotifGuide(titre: "Resucrage en nuit profonde",
                   detail: "Des glucides ont été pris dans la fenêtre mesurée.",
                   icone: "cross.case.fill"),
        MotifGuide(titre: "Glycémie instable",
                   detail: "La courbe est trop chaotique pour qu'une pente moyenne veuille dire quelque chose.",
                   icone: "waveform.path"),
        MotifGuide(titre: "Couverture CGM insuffisante",
                   detail: "Trop de mesures manquent sur la fenêtre.",
                   icone: "wifi.slash")
    ]
}

// MARK: - Courbe d'exemple

/// Mini-courbe fabriquée pour illustrer un cas — **aucune donnée réelle**.
/// La portion analysée est teintée, le reste est gris.
private struct CourbeGuide: View {

    let points: [Double]
    /// Fraction de la largeur correspondant à la nuit profonde.
    let zoneAnalysee: ClosedRange<Double>
    let teinte: Color

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { index, valeur in
                LineMark(
                    x: .value("t", Double(index) / Double(points.count - 1)),
                    y: .value("mg/dL", valeur)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color(.systemGray2))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            RectangleMark(
                xStart: .value("d", zoneAnalysee.lowerBound),
                xEnd: .value("f", zoneAnalysee.upperBound)
            )
            .foregroundStyle(teinte.opacity(0.12))
        }
        .chartXScale(domain: 0...1)
        .chartYScale(domain: 50...220)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 78)
    }

    // Séries d'exemple — valeurs choisies pour illustrer, pas mesurées.
    static let stable: [Double] = [150, 138, 130, 126, 122, 120, 118, 121, 119, 124, 138]
    static let descendante: [Double] = [165, 155, 148, 140, 128, 112, 96, 84, 78, 82, 95]
    static let ascendante: [Double] = [110, 112, 115, 118, 128, 142, 158, 172, 180, 186, 195]
    static let amelioration: [Double] = [175, 168, 155, 140, 132, 126, 122, 120, 118, 120, 128]
}

// MARK: - Aperçus

#if DEBUG
#Preview {
    SheetGuideTendanceBasale()
}
#endif
