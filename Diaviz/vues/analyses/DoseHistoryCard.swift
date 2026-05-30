//
//  DoseHistoryCard.swift
//  diaviz
//
//  Created by Alexandre on 26/05/2026.
//

import SwiftUI

/// Carte 4 — **Historique de dose** sous forme de timeline verticale.
///
/// Ligne fine à gauche, un dot par changement de dose, infos à droite
/// (dose + période). Le plus récent en haut. Limité à 5 entrées
/// visibles ; au-delà, un lien « Voir tout » ouvre une sheet complète.
/// En bas un récap textuel résume l'activité.
struct DoseHistoryCard: View {

    /// Triés du plus récent au plus ancien.
    let changes: [DoseChange]

    /// Action déclenchée par le lien « Voir tout » quand il y a plus
    /// de 5 changements. `nil` si non câblé — le lien est alors masqué.
    var onSeeAll: (() -> Void)? = nil

    private static let maxAffichees = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titre
            timeline
            recap
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Titre

    private var titre: some View {
        Text("Historique de dose")
            .font(.system(size: 16, weight: .medium))
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Timeline verticale

    private var changesAffichees: [DoseChange] {
        Array(changes.prefix(Self.maxAffichees))
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(changesAffichees.enumerated()), id: \.element.id) { (idx, change) in
                LigneChangement(
                    change: change,
                    estDernierePresente: idx == changesAffichees.count - 1
                )
            }
            if changes.count > Self.maxAffichees, let onSeeAll {
                Button(action: onSeeAll) {
                    Text("Voir tout")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tint)
                }
                .padding(.leading, 22)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Récap

    private var recap: some View {
        Text(libelleRecap)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }

    private var libelleRecap: String {
        let nbChangements = max(0, changes.count - 1)
        if nbChangements == 0, let current = changes.first {
            let jours = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: current.startDate),
                to: Calendar.current.startOfDay(for: Date.now)
            ).day ?? 0
            return "Aucun changement depuis \(jours) jours"
        }
        // Couverture totale en mois (approx).
        guard let dernier = changes.last else { return "" }
        let jours = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: dernier.startDate),
            to: Calendar.current.startOfDay(for: Date.now)
        ).day ?? 0
        let moisApprox = max(1, jours / 30)
        return "\(nbChangements) changements sur \(moisApprox) mois"
    }
}

// MARK: - Une ligne de la timeline

private struct LigneChangement: View {

    let change: DoseChange
    let estDernierePresente: Bool

    /// Couleur du dot — teal accent pour la dose en cours, gris pour
    /// les anciennes. Le `Color.teal` adapte automatiquement clair/sombre.
    private var couleurDot: Color {
        change.isCurrent ? .teal : .secondary.opacity(0.6)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Colonne timeline : ligne verticale + dot.
            ZStack(alignment: .top) {
                if !estDernierePresente {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                        .padding(.top, 14)
                }
                Circle()
                    .fill(couleurDot)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
            .frame(width: 10)

            // Colonne texte (dose + période + badge actuel).
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("\(libelleDose(change.dose))u")
                        .font(.system(size: 15, weight: .medium))
                        .monospacedDigit()
                    if change.isCurrent {
                        Text("actuelle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18))
                            .clipShape(Capsule(style: .continuous))
                    }
                }
                Text(libellePeriode)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible)
    }

    // MARK: - Formatage

    private func libelleDose(_ d: Double) -> String {
        d == floor(d) ? String(format: "%.0f", d) : String(format: "%.1f", d)
    }

    /// « depuis le 20 mai (6 jours) » pour la dose actuelle,
    /// « 12 → 20 mai (8 jours) » pour les anciennes.
    private var libellePeriode: String {
        let cal = Calendar.current
        let now = Date.now

        if let endDate = change.endDate {
            let dureeJ = cal.dateComponents([.day], from: cal.startOfDay(for: change.startDate),
                                            to: cal.startOfDay(for: endDate)).day ?? 0
            let debut = jourMoisCourt(change.startDate, avecMois: !memeMois(change.startDate, endDate))
            let fin = jourMoisCourt(endDate, avecMois: true)
            return "\(debut) → \(fin) (\(formuleJours(dureeJ)))"
        } else {
            let dureeJ = cal.dateComponents([.day], from: cal.startOfDay(for: change.startDate),
                                            to: cal.startOfDay(for: now)).day ?? 0
            return "depuis le \(jourMoisCourt(change.startDate, avecMois: true)) (\(formuleJours(dureeJ)))"
        }
    }

    private func jourMoisCourt(_ date: Date, avecMois: Bool) -> String {
        if avecMois {
            return date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
        }
        return String(Calendar.current.component(.day, from: date))
    }

    private func memeMois(_ a: Date, _ b: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.month, from: a) == cal.component(.month, from: b)
            && cal.component(.year, from: a) == cal.component(.year, from: b)
    }

    private func formuleJours(_ n: Int) -> String {
        n == 1 ? "1 jour" : "\(n) jours"
    }

    private var libelleAccessible: String {
        let dose = "\(libelleDose(change.dose)) unités"
        return change.isCurrent
            ? "Dose actuelle \(dose), \(libellePeriode)"
            : "Ancienne dose \(dose), \(libellePeriode)"
    }
}

// MARK: - Aperçus

#Preview("Historique - 4 changements") {
    DoseHistoryCard(changes: AnalyseBasaleDetail.mockStandard14j.doseHistory)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Historique - 1 seul changement (no data)") {
    DoseHistoryCard(changes: AnalyseBasaleDetail.mockNoData.doseHistory)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Historique - Changement récent") {
    DoseHistoryCard(changes: AnalyseBasaleDetail.mockRecentChange.doseHistory)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
