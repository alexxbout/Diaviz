//
//  CarteIOB.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import SwiftUI
import Charts

/// Carte "Insuline active" (IOB — Insulin On Board) — deuxième carte
/// de la grille d'accueil. Affiche en gros la quantité d'insuline
/// rapide encore active dans le corps, exprimée en unités.
///
/// La valeur reste en couleur primaire (texte normal) — pas de code
/// couleur par palier : l'IOB élevé n'est pas une alerte en soi, et
/// le chiffre + la courbe parlent d'eux-mêmes. Le rouge reste réservé
/// aux vrais signaux d'alerte (cf. carte Hypos).
///
/// L'icône reste bleue (#378ADD) pour rappeler la sémantique "insuline"
/// du symbole `drop.fill`, indépendamment du niveau.
///
/// Une **mini-courbe de décroissance IOB** sur les 6h à venir est
/// rendue en bas de la carte quand de l'insuline est active. La
/// courbe est calculée à partir d'un modèle Hermite cubique lisse
/// (cf. `iobResiduel`) qui gère naturellement la superposition de
/// plusieurs injections et la forme d'une ultra-rapide moderne. Si
/// IOB ≈ 0, la courbe est remplacée par un sous-libellé "Aucune
/// insuline active" pour équilibrer la masse visuelle.
struct CarteIOB: View {

    /// IOB en unités. Peut être nul ou très faible — la carte
    /// affichera alors "0.0u" en couleur primaire et masquera la courbe.
    let valeur: Double

    /// Courbe d'IOB total projetée — précalculée par le service mock
    /// (ou à terme la couche d'analyses) pour éviter tout recalcul à
    /// chaque render.
    let pointsIOB: [PointIOB]

    /// Seuil sous lequel on considère que "plus rien n'est actif". La
    /// barre de 0.05u absorbe les valeurs résiduelles infinitésimales
    /// de la courbe — on évite d'afficher une courbe quasi-plate.
    private var afficherCourbe: Bool {
        valeur >= 0.05 && !pointsIOB.isEmpty
    }

    var body: some View {
        CarteMetriqueShell {
            // VStack spacing 0 + paddings explicites — voir la note
            // sur l'alignement des valeurs dans `CarteHypos`.
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Ligne icône + titre (haut)
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.footnote)
                        .foregroundStyle(couleurIcone)
                        .accessibilityHidden(true)
                    Text("Insuline active")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                // MARK: Valeur principale + unité collée (Y fixe)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(valeurFormatee)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("u")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .padding(.top, 24)

                // MARK: Sous-libellé "rien d'actif" — collé sous la
                // valeur quand l'IOB est négligeable (le chart est
                // alors masqué).
                if !afficherCourbe {
                    Text("Aucune insuline active")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)

                // MARK: Courbe IOB (ancrée en bas)
                if afficherCourbe {
                    courbeIOB
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Insuline active : \(valeurFormatee) unités")
    }

    /// Mini-courbe de décroissance Swift Charts — 24pt de haut, sans
    /// axe ni légende. Trois couches : zone bleue diluée sous la
    /// courbe, ligne bleue plus marquée, point coloré au temps zéro
    /// (couleur identique à celle de la valeur principale).
    private var courbeIOB: some View {
        Chart {
            // AreaMark + LineMark pour chaque échantillon — Swift
            // Charts assemble les ForEach par type de mark.
            ForEach(pointsIOB, id: \.minutesDepuisMaintenant) { point in
                AreaMark(
                    x: .value("Temps", point.minutesDepuisMaintenant),
                    y: .value("IOB", point.iob)
                )
                .foregroundStyle(Color.blue.opacity(0.12))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Temps", point.minutesDepuisMaintenant),
                    y: .value("IOB", point.iob)
                )
                .foregroundStyle(Color.blue.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            // Marqueur "maintenant" — épingle visuelle dans la teinte
            // "insuline" pour rester raccord avec l'icône.
            if let premier = pointsIOB.first {
                PointMark(
                    x: .value("Temps", 0),
                    y: .value("IOB", premier.iob)
                )
                .foregroundStyle(couleurIcone)
                .symbolSize(36)
            }

            // Repère vertical à la fin de la courbe — pointillé subtil
            // qui ancre visuellement l'étiquette d'axe « dans 2h15 ».
            if let dernier = pointsIOB.last, dernier.minutesDepuisMaintenant > 0 {
                RuleMark(x: .value("Fin", dernier.minutesDepuisMaintenant))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
            }
        }
        .chartXAxis {
            // Un seul tick à la fin de la courbe : indique en combien
            // de temps il n'y aura plus d'insuline active. Pas de
            // ligne d'axe ni de tick visible — juste l'étiquette.
            AxisMarks(values: [minutesJusquAFin]) { _ in
                AxisValueLabel(anchor: .topTrailing) {
                    Text("dans \(formatDuree(minutesJusquAFin))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 52)
    }

    /// Minutes restantes avant que l'IOB total tombe à zéro — c'est
    /// l'abscisse du dernier point de la courbe. Retourne 0 si la
    /// courbe est vide (auquel cas le chart n'est pas affiché).
    private var minutesJusquAFin: Int {
        pointsIOB.last?.minutesDepuisMaintenant ?? 0
    }

    /// Format court d'une durée en minutes — « 45 min », « 2h », « 2h15 ».
    /// Identique en esprit au format de `CarteDerniereInjection` mais
    /// sans le préfixe « il y a » (on parle ici du futur).
    private func formatDuree(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 { return "\(h)h" }
        return "\(h)h\(String(format: "%02d", m))"
    }

    // MARK: - Apparence dérivée du niveau

    /// Icône en bleu "insuline" (#378ADD), constant indépendamment du
    /// niveau — c'est le chiffre qui porte l'alerte.
    private var couleurIcone: Color {
        Color(red: 0x37 / 255, green: 0x8A / 255, blue: 0xDD / 255)
    }

    /// Format à 1 décimale — cohérent avec le reste de l'app (cf.
    /// `BadgeIOB`) et lisible pour des valeurs typiques 0.0–6.0u.
    private var valeurFormatee: String {
        String(format: "%.1f", valeur)
    }
}

// MARK: - Aperçus

#Preview("IOB - 3.2u avec courbe") {
    CarteIOB(
        valeur: MetriquesAccueil.mockNormal.iob,
        pointsIOB: MetriquesAccueil.mockNormal.pointsIOB
    )
    .frame(width: 170, height: 180)
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("IOB - 4.4u élevé") {
    CarteIOB(
        valeur: MetriquesAccueil.mockAlerte.iob,
        pointsIOB: MetriquesAccueil.mockAlerte.pointsIOB
    )
    .frame(width: 170, height: 180)
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("IOB - 0u sans courbe") {
    CarteIOB(valeur: 0, pointsIOB: [])
        .frame(width: 170, height: 180)
        .padding()
        .background(Color(.systemGroupedBackground))
}
