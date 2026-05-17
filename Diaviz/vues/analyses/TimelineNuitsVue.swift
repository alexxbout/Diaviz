//
//  TimelineNuitsVue.swift
//  diaviz
//
//  Created by Alexandre on 17/05/2026.
//

import SwiftUI

/// Carte 2 — **timeline 14 nuits** : une colonne par nuit avec un point
/// indiquant l'état (valide / exclue / sans données / en cours), reliés
/// par un trait vert continu pour les nuits incluses dans l'analyse.
///
/// La timeline permet de répondre d'un coup d'œil à la question « quelles
/// nuits ont compté dans le verdict ? » sans avoir à dérouler le détail
/// de chaque nuit. Tapper un point gris affiche la raison d'exclusion
/// pendant 3 secondes (par ex. « Sport à 19h30 »).
///
/// Visuellement alignée avec le langage des cartes voisines : padding
/// 20pt, `Radius.large`, fond `secondarySystemGroupedBackground`. Le
/// composant ne porte pas de logique d'analyse — il consomme la
/// `[NuitTimeline]` déjà produite par le service.
struct TimelineNuitsVue: View {

    let timeline: [NuitTimeline]

    /// Cellule actuellement sélectionnée (raison d'exclusion en cours
    /// d'affichage). Auto-effacée par une `Task` après 3 secondes.
    @State private var raisonAffichee: RaisonAffichee?

    /// Respecte « Réduire les animations » système pour la transition
    /// d'apparition/disparition du message d'exclusion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titre
            ligneTimeline
            slotMessage
            legende
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Titre

    private var titre: some View {
        Text("Nuits analysées")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Timeline (Canvas pour la ligne, ZStack pour les points)

    /// Hauteur de la rangée de points — choisie pour laisser ~32pt de
    /// hauteur de tap target par cellule (la largeur étant contrainte
    /// par les 14 colonnes sur la largeur de la carte, on compense en
    /// hauteur pour rester confortable au doigt).
    private static let hauteurRangeePoints: CGFloat = 32

    private var ligneTimeline: some View {
        VStack(spacing: 6) {
            // Couche dots + ligne de liaison : la ligne est dessinée
            // *derrière* les points via un ZStack — Canvas occupe toute
            // la largeur et trace un segment entre chaque paire de nuits
            // valides consécutives.
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

            // Initiales des jours sous les points.
            HStack(spacing: 0) {
                ForEach(timeline) { nuit in
                    Text(initialeJour(nuit.date))
                        .font(.system(size: 9))
                        .fontWeight(estAujourdhui(nuit.date) ? .bold : .regular)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibleTimeline)
    }

    // MARK: - Point d'une nuit (cercle stylé selon l'état)

    /// Pas de `.frame(width:)` ici : la cellule prend la **part égale**
    /// imposée par l'`HStack` parent (chaque colonne = largeur dispo / 14).
    /// Forcer une largeur minimale en pt forcerait la timeline à dépasser
    /// la largeur de l'écran (14 × 32 = 448pt > ~358pt utile sur iPhone)
    /// et toutes les cartes voisines hériteraient de l'overflow.
    @ViewBuilder
    private func pointNuit(_ nuit: NuitTimeline) -> some View {
        let estSelectionnee = (raisonAffichee?.id == nuit.id)

        Button {
            handleTap(nuit)
        } label: {
            cerclePourEtat(nuit.etat, avantChangementDose: nuit.avantChangementDose)
                .opacity(nuit.avantChangementDose ? 0.35 : 1)
                .scaleEffect(estSelectionnee ? 1.4 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                           value: estSelectionnee)
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

    // MARK: - Slot raison d'exclusion (3 s après tap)

    /// Hauteur réservée pour que l'apparition/disparition du message ne
    /// fasse pas bouger la légende ni les cartes suivantes — `16pt`
    /// suffit pour une ligne en `.caption`.
    private var slotMessage: some View {
        Text(raisonAffichee?.raison.rawValue ?? " ")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 16)
            .opacity(raisonAffichee == nil ? 0 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: raisonAffichee?.id)
            .accessibilityHidden(raisonAffichee == nil)
    }

    // MARK: - Légende

    private var legende: some View {
        HStack(spacing: 16) {
            puceLegende(forme: .pleine(.green), texte: "Valide")
            puceLegende(forme: .vide, texte: "Exclue")
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

    private func handleTap(_ nuit: NuitTimeline) {
        guard case .exclue(let raison) = nuit.etat else { return }
        let nouvelle = RaisonAffichee(id: nuit.id, raison: raison)
        raisonAffichee = nouvelle
        Task {
            try? await Task.sleep(for: .seconds(3))
            // Évite d'effacer si l'utilisateur a tapé une autre nuit
            // entre-temps — on ne dégage que SA propre cellule.
            if raisonAffichee?.id == nouvelle.id {
                raisonAffichee = nil
            }
        }
    }

    // MARK: - Formatage / accessibilité

    /// Première lettre du jour de la semaine en français : L M M J V S D.
    /// Locale forcée pour rester stable même si le simulateur tourne en
    /// anglais (sinon `Date.formatted` renverrait « M T W T F S S »).
    private func initialeJour(_ date: Date) -> String {
        let s = date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "fr_FR")))
        return s.uppercased()
    }

    private func estAujourdhui(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func libelleAccessibleNuit(_ nuit: NuitTimeline) -> String {
        let dateLib = nuit.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
        switch nuit.etat {
        case .valide:       return "\(dateLib), nuit valide"
        case .exclue(let r): return "\(dateLib), nuit exclue : \(r.rawValue)"
        case .sansDonnees:  return "\(dateLib), pas de données"
        case .enCours:      return "\(dateLib), nuit en cours"
        }
    }

    private var libelleAccessibleTimeline: String {
        let valides = timeline.filter { $0.etat.estValide }.count
        let exclues = timeline.filter { if case .exclue = $0.etat { return true } else { return false } }.count
        return "Timeline 14 jours. \(valides) nuits valides, \(exclues) exclues."
    }

    // MARK: - État du popover

    /// `Identifiable` + `Equatable` pour piloter `.animation(value:)` sur
    /// la transition entre deux cellules sélectionnées.
    private struct RaisonAffichee: Equatable {
        let id: UUID
        let raison: RaisonExclusion
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

#Preview("Timeline - Données insuffisantes") {
    TimelineNuitsVue(timeline: AnalyseBasaleDetail.mockInsuffisant.timeline)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
