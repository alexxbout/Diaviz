//
//  RepartitionNuitsVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Carte 3 — barre horizontale segmentée (vert/orange/rouge) résumant
/// la **répartition** des nuits analysées par catégorie, suivie d'une
/// liste de métriques détaillées.
///
/// Même langage visuel que la `BarreAGP` du score (segments accolés,
/// pourcentage en blanc centré si ≥ 15 %, hauteur 32 pt, coin 8 pt) —
/// l'utilisateur retrouve un pattern qu'il connaît déjà.
struct RepartitionNuitsVue: View {

    let analyse: AnalyseBasaleDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titre
            barreSegmentee
            listeMetriques
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Titre de section

    private var titre: some View {
        Text("Répartition")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Barre segmentée

    private var barreSegmentee: some View {
        BarreNuits(
            stables: analyse.nuitsStables,
            basses: analyse.nuitsTendanceBasse,
            hautes: analyse.nuitsTendanceHaute
        )
    }

    // MARK: - Métriques détaillées

    private var listeMetriques: some View {
        VStack(alignment: .leading, spacing: 10) {
            ligneMetrique(icone: "moon.fill", couleurIcone: .secondary,
                          label: "Nuits stables",
                          valeur: "\(analyse.nuitsStables)")
            ligneMetrique(icone: "arrow.down.right", couleurIcone: .orange,
                          label: "Nuits tendance basse",
                          valeur: "\(analyse.nuitsTendanceBasse)")
            ligneMetrique(icone: "arrow.up.right", couleurIcone: .red,
                          label: "Nuits tendance haute",
                          valeur: "\(analyse.nuitsTendanceHaute)")
            ligneMetrique(icone: "circle.dashed", couleurIcone: .secondary,
                          label: "Nuits exclues",
                          valeur: "\(analyse.nuitsExclues)")

            Divider()

            ligneMetrique(icone: "exclamationmark.triangle.fill", couleurIcone: .red,
                          label: "Hypos nocturnes",
                          valeur: "\(analyse.hyposNocturnes)")
            ligneMetrique(icone: "arrow.triangle.2.circlepath", couleurIcone: .orange,
                          label: "Resucrages avec rechute",
                          valeur: "\(analyse.resucragesAvecRechute)")

            Divider()

            ligneMetrique(icone: "sunrise.fill", couleurIcone: .blue,
                          label: "Glycémie moy. réveil",
                          valeur: "\(analyse.glycemieMoyenneReveil) mg/dL")
        }
        .padding(.top, 16)
    }

    private func ligneMetrique(icone: String, couleurIcone: Color, label: String, valeur: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icone)
                .font(.caption)
                .foregroundStyle(couleurIcone)
                .frame(width: 18, alignment: .center)
                .accessibilityHidden(true)

            Text(label)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Text(valeur)
                .font(.body.bold())
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(valeur)")
    }
}

// MARK: - Barre horizontale segmentée (interne à la carte)

/// Barre 32 pt segmentée par les 3 catégories de nuit. Largeur de
/// chaque segment au prorata du nombre de nuits ; pourcentage affiché
/// en blanc centré uniquement si ≥ 15 % pour éviter le texte illisible
/// sur les segments fins.
///
/// Couleurs choisies pour rester cohérentes avec la barre AGP du score
/// (`#1D9E75` vert, `#EF9F27` orange) et avec la sémantique « risque »
/// utilisée ailleurs dans l'app (`#E24B4A` rouge clair pour les nuits
/// trop hautes — pattern de basale insuffisante).
private struct BarreNuits: View {

    let stables: Int
    let basses: Int
    let hautes: Int

    private static let hauteur: CGFloat = 32
    private static let coinArrondi: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = max(1, stables + basses + hautes)
            HStack(spacing: 0) {
                Segment(couleur: Color(red: 0.114, green: 0.620, blue: 0.459),
                        pourcent: pourcent(stables, sur: total))
                    .frame(width: largeur(stables, sur: total, total: geo.size.width))
                Segment(couleur: Color(red: 0.937, green: 0.624, blue: 0.153),
                        pourcent: pourcent(basses, sur: total))
                    .frame(width: largeur(basses, sur: total, total: geo.size.width))
                Segment(couleur: Color(red: 0.886, green: 0.294, blue: 0.290),
                        pourcent: pourcent(hautes, sur: total))
                    .frame(width: largeur(hautes, sur: total, total: geo.size.width))
            }
        }
        .frame(height: Self.hauteur)
        .clipShape(RoundedRectangle(cornerRadius: Self.coinArrondi, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(libelleAccessible)
    }

    private func pourcent(_ n: Int, sur total: Int) -> Double {
        100 * Double(n) / Double(total)
    }

    private func largeur(_ n: Int, sur total: Int, total largeurTotale: CGFloat) -> CGFloat {
        largeurTotale * CGFloat(n) / CGFloat(total)
    }

    private var libelleAccessible: String {
        let total = stables + basses + hautes
        return "Répartition sur \(total) nuits : \(stables) stables, \(basses) tendance basse, \(hautes) tendance haute."
    }
}

/// Segment de la `BarreNuits` — remplissage couleur + pourcentage
/// blanc centré au-dessus de 15 % (en dessous l'espace est trop étroit
/// pour rester lisible).
private struct Segment: View {

    let couleur: Color
    let pourcent: Double

    var body: some View {
        ZStack {
            couleur
            if pourcent >= 15 {
                Text(String(format: "%.0f %%", pourcent))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Aperçus

#Preview("Répartition - Trop haute") {
    RepartitionNuitsVue(analyse: .mockTropHaute)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Répartition - Adaptée") {
    RepartitionNuitsVue(analyse: .mockAdaptee)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Répartition - Données insuffisantes") {
    RepartitionNuitsVue(analyse: .mockInsuffisant)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
