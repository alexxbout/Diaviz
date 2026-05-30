//
//  TimelineNuitsVue.swift
//  diaviz
//
//  Created by Alexandre on 17/05/2026.
//

import SwiftUI

/// Carte 2 — **timeline 14 jours « Périodes analysées »** : une colonne
/// par nuit avec un point indiquant si au moins une zone a été
/// analysable, reliés par un trait vert continu pour les nuits
/// incluses dans l'analyse.
///
/// Catégories visuelles :
///   - cercle plein vert → au moins 1 zone analysée
///   - cercle vide gris → nuit présente mais aucune zone exploitable
///   - cercle pointillé gris → pas de données CGM
///   - cercle plein bleu → nuit en cours
///
/// Tap sur un dot → callback `onNightSelected(date)` (le parent
/// bascule la vue « Par nuit » sur cette date).
struct TimelineNuitsVue: View {

    let timeline: [NuitTimeline]
    var onNightSelected: ((Date) -> Void)? = nil

    /// Respecte « Réduire les animations » système pour la transition
    /// d'apparition/disparition du message d'exclusion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Suivi de la cellule récemment tappée — utilisé pour l'effet de
    /// scale brièvement appliqué au point en confirmation visuelle du
    /// tap.
    @State private var idTapEnCours: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titre
            ligneTimeline
            legende
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Titre

    private var titre: some View {
        Text("Périodes analysées")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Timeline (Canvas pour la ligne, ZStack pour les points)

    /// Hauteur de la rangée de points — tap target ~32pt vertical.
    private static let hauteurRangeePoints: CGFloat = 32

    private var ligneTimeline: some View {
        VStack(spacing: 4) {
            // Couche dots + ligne de liaison.
            ZStack {
                Canvas { ctx, size in
                    let n = CGFloat(timeline.count)
                    guard n > 1 else { return }
                    let pas = size.width / n
                    let y = size.height / 2
                    for i in 0..<(timeline.count - 1) {
                        let curr = timeline[i]
                        let next = timeline[i + 1]
                        guard curr.etat.estValide, next.etat.estValide else { continue }
                        let x1 = pas * (CGFloat(i) + 0.5)
                        let x2 = pas * (CGFloat(i + 1) + 0.5)
                        var path = Path()
                        path.move(to: CGPoint(x: x1, y: y))
                        path.addLine(to: CGPoint(x: x2, y: y))
                        ctx.stroke(path, with: .color(.green.opacity(0.6)), lineWidth: 1)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(timeline) { nuit in
                        pointNuit(nuit)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.hauteurRangeePoints)

            // Lettre + numéro du jour sous chaque colonne.
            HStack(spacing: 0) {
                ForEach(timeline) { nuit in
                    VStack(spacing: 1) {
                        Text(initialeJour(nuit.date))
                            .font(.system(size: 9))
                            .fontWeight(estAujourdhui(nuit.date) ? .bold : .regular)
                            .foregroundStyle(.tertiary)
                        Text(numeroJour(nuit.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibleTimeline)
    }

    // MARK: - Point d'une nuit (cercle stylé selon l'état)

    @ViewBuilder
    private func pointNuit(_ nuit: NuitTimeline) -> some View {
        let estPressee = (idTapEnCours == nuit.id)

        Button {
            handleTap(nuit)
        } label: {
            cerclePourEtat(nuit.etat, avantChangementDose: nuit.avantChangementDose)
                .opacity(nuit.avantChangementDose ? 0.35 : 1)
                .scaleEffect(estPressee ? 1.4 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                           value: estPressee)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelleAccessibleNuit(nuit))
    }

    @ViewBuilder
    private func cerclePourEtat(_ etat: EtatNuit, avantChangementDose: Bool) -> some View {
        switch etat {
        case .valide:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        case .exclue:
            Circle()
                .stroke(Color.secondary, lineWidth: 1.5)
                .frame(width: 8, height: 8)
        case .sansDonnees:
            Circle()
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 1.5]))
                .frame(width: 8, height: 8)
        case .enCours:
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Légende

    private var legende: some View {
        HStack(spacing: 16) {
            puceLegende(forme: .pleine(.green), texte: "Analysable")
            puceLegende(forme: .vide, texte: "Non exploitable")
            puceLegende(forme: .pointille, texte: "Pas de données")
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }

    private enum FormePuce {
        case pleine(Color)
        case vide
        case pointille
    }

    @ViewBuilder
    private func puceLegende(forme: FormePuce, texte: String) -> some View {
        HStack(spacing: 4) {
            switch forme {
            case .pleine(let couleur):
                Circle().fill(couleur).frame(width: 8, height: 8)
            case .vide:
                Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
            case .pointille:
                Circle()
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 1.5]))
                    .frame(width: 8, height: 8)
            }
            Text(texte)
        }
    }

    // MARK: - Interaction

    /// Sur tap : flash visuel court + notification du parent via le
    /// callback (le parent s'occupe de basculer la vue Par nuit).
    private func handleTap(_ nuit: NuitTimeline) {
        idTapEnCours = nuit.id
        onNightSelected?(nuit.date)
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            if idTapEnCours == nuit.id {
                idTapEnCours = nil
            }
        }
    }

    // MARK: - Formatage / accessibilité

    /// Première lettre du jour de la semaine en français : L M M J V S D.
    private func initialeJour(_ date: Date) -> String {
        let s = date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "fr_FR")))
        return s.uppercased()
    }

    /// Numéro du jour dans le mois (« 13 », « 04 »).
    private func numeroJour(_ date: Date) -> String {
        let comp = Calendar.current.component(.day, from: date)
        return String(comp)
    }

    private func estAujourdhui(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func libelleAccessibleNuit(_ nuit: NuitTimeline) -> String {
        let dateLib = nuit.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
        switch nuit.etat {
        case .valide:       return "\(dateLib), analysable. Toucher pour ouvrir."
        case .exclue:       return "\(dateLib), non exploitable. Toucher pour ouvrir."
        case .sansDonnees:  return "\(dateLib), pas de données"
        case .enCours:      return "\(dateLib), nuit en cours"
        }
    }

    private var libelleAccessibleTimeline: String {
        let valides = timeline.filter { $0.etat.estValide }.count
        let exclues = timeline.filter { if case .exclue = $0.etat { return true } else { return false } }.count
        return "Timeline 14 jours. \(valides) nuits analysables, \(exclues) non exploitables."
    }
}

// MARK: - Aperçus

#Preview("Timeline - Standard") {
    TimelineNuitsVue(timeline: AnalyseBasaleDetail.mockStandard14j.timeline)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Timeline - Changement de dose") {
    TimelineNuitsVue(timeline: AnalyseBasaleDetail.mockChangementDose.timeline)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Timeline - No data") {
    TimelineNuitsVue(timeline: AnalyseBasaleDetail.mockNoData.timeline)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
