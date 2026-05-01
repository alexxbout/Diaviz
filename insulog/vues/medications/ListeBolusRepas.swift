//
//  ListeBolusRepas.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Liste lecture seule des bolus repas (rapide pour repas) du jour
/// affiché. La saisie se fait depuis la page Repas — ici on se contente
/// de les exposer pour cohérence avec le reste de la timeline.
///
/// S'utilise comme contenu d'une `Section` de `List` — vide
/// intentionnellement de tout chrome ; le parent gère la `Section`
/// (header « BOLUS REPAS » + sous-titre « Saisis via la page Repas »).
struct ListeBolusRepas: View {

    let bolus: [Injection]

    var body: some View {
        ForEach(bolus) { b in
            ligne(b)
                .id(b.id)
        }
    }

    @ViewBuilder
    private func ligne(_ b: Injection) -> some View {
        HStack(spacing: 12) {
            Text(b.emojiRepas ?? "🍽️")
                .font(.title3)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(formate(b.dose))u")
                        .font(.body.bold())
                        .monospacedDigit()
                    if let label = b.labelRepas {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(label)
                            .font(.body.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(b.libelleSite)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(b.heure, format: .dateTime.hour().minute())
                .font(.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibilite(b))
    }

    private func libelleAccessibilite(_ b: Injection) -> String {
        let label = b.labelRepas ?? "repas"
        return "Bolus \(label) de \(formate(b.dose)) unités à \(b.heure.formatted(date: .omitted, time: .shortened)), \(b.libelleSite). Lecture seule."
    }

    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }
}

// MARK: - Aperçu

#Preview("Avec bolus") {
    let bolus = [
        Injection(
            type: .rapideRepas, dose: 4,
            heure: Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date()) ?? Date(),
            zoneInjection: .ventre, coteInjection: .droite,
            labelRepas: "Petit-déjeuner", emojiRepas: "🍞"
        ),
        Injection(
            type: .rapideRepas, dose: 6.5,
            heure: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date()) ?? Date(),
            zoneInjection: .ventre, coteInjection: .gauche,
            labelRepas: "Déjeuner", emojiRepas: "🍝"
        ),
    ]
    return List {
        Section {
            ListeBolusRepas(bolus: bolus)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("BOLUS REPAS")
                Text("Saisis via la page Repas")
                    .textCase(nil)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    .listStyle(.insetGrouped)
}
