//
//  ListeCorrections.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Liste des injections de correction (rapide hors repas) du jour
/// affiché. S'utilise comme contenu d'une `Section` de `List` —
/// les rows héritent automatiquement du style natif (separators,
/// padding, fond `secondarySystemGroupedBackground`).
///
/// Vide intentionnellement de tout chrome (header, container) :
/// le parent gère la `Section` avec son header « CORRECTIONS » et
/// le placeholder d'état vide.
struct ListeCorrections: View {

    let corrections: [Injection]
    let onTap: (Injection) -> Void
    let onSupprimer: (Injection) -> Void

    /// Trigger du retour haptique à la suppression (swipe).
    @State private var triggerSuppression: Int = 0

    var body: some View {
        ForEach(corrections) { c in
            ligne(c)
                .id(c.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onSupprimer(c)
                        triggerSuppression += 1
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
        }
        .sensoryFeedback(.warning, trigger: triggerSuppression)
    }

    @ViewBuilder
    private func ligne(_ c: Injection) -> some View {
        Button {
            onTap(c)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formate(c.dose))u")
                        .font(.body.bold())
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text(libelleSousLigne(c))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(c.heure, format: .dateTime.hour().minute())
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibilite(c))
        .accessibilityHint("Touchez deux fois pour modifier")
    }

    /// « Bras droit · 165 mg/dL » si glycémie connue, sinon juste la zone.
    /// La glycémie « après » sera dérivée du CGM quand l'API sera branchée.
    private func libelleSousLigne(_ c: Injection) -> String {
        if let glyc = c.glycemieAuMoment {
            return "\(c.libelleSite) · \(Int(glyc)) mg/dL"
        }
        return c.libelleSite
    }

    private func libelleAccessibilite(_ c: Injection) -> String {
        var s = "Correction de \(formate(c.dose)) unités à \(c.heure.formatted(date: .omitted, time: .shortened)), \(c.libelleSite)"
        if let glyc = c.glycemieAuMoment {
            s += ", glycémie \(Int(glyc)) milligrammes par décilitre"
        }
        return s
    }

    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Avec corrections") {
    let corrections = [
        Injection(
            type: .rapideCorrection, dose: 1.5,
            heure: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date()) ?? Date(),
            zoneInjection: .bras, coteInjection: .droite,
            glycemieAuMoment: 165
        ),
        Injection(
            type: .rapideCorrection, dose: 0.5,
            heure: Calendar.current.date(bySettingHour: 9, minute: 15, second: 0, of: Date()) ?? Date(),
            zoneInjection: .ventre, coteInjection: .gauche,
            glycemieAuMoment: 240
        ),
    ]
    return List {
        Section("Corrections") {
            ListeCorrections(corrections: corrections, onTap: { _ in }, onSupprimer: { _ in })
        }
    }
    .listStyle(.insetGrouped)
}
#endif
