//
//  InsulineSection.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Section "INSULINE" de la `RepasSheet`.
///
/// Sépare deux notions distinctes :
/// - **Ajustements intentionnels** (liste éditable, valeurs signées) : raisons
///   parmi sport récent, glycémie basse, repas gras, incertitude glucides,
///   IOB, autre. Ajout via bouton dédié, édition via tap sur la row, suppression
///   via swipe ou bouton dans la sheet d'édition.
/// - **Correction hyperglycémie** (toujours positive) : dose additive pour
///   compenser une glycémie élevée AVANT le repas.
///
/// Le total injecté = dose des aliments + somme des ajustements (signés) + correction hyper.
struct InsulineSection: View {

    let doseRepas: Double
    @Binding var ajustements: [Ajustement]
    @Binding var correctionHyper: Double
    /// Dose unique pour tout le repas — `nil` = mode classique (dose par
    /// aliment). La valeur EST le flag : le toggle la crée (préremplie avec
    /// la somme des doses par aliment, rien n'est perdu en basculant) et la
    /// remet à `nil` en se désactivant.
    @Binding var doseGlobale: Double?
    /// Pré-calculé par le parent pour rester cohérent avec ses propres calculs.
    let totalInjecte: Double

    /// Callbacks pour ouvrir la sheet d'ajustement (gérée par le parent).
    let onAjouterAjustement: () -> Void
    let onEditerAjustement: (Ajustement) -> Void

    var body: some View {
        Section {
            toggleDoseGlobale
            if doseGlobale != nil {
                doseGlobaleRow
            } else {
                doseRepasRow
            }
            correctionHyperRow
            ajustementsRows
            boutonAjouterAjustement
            totalInjecteRow
        } header: {
            Text("Insuline")
        }
    }

    // MARK: - Rows

    /// Bascule entre dose ventilée par aliment et dose unique pour le repas.
    private var toggleDoseGlobale: some View {
        Toggle(isOn: Binding(
            get: { doseGlobale != nil },
            set: { actif in
                doseGlobale = actif ? doseRepas : nil
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dose globale")
                    .font(.body)
                Text("Une seule dose pour tout le repas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var doseRepasRow: some View {
        LabeledContent {
            Text(formate(doseRepas) + "u")
                .font(.body.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: doseRepas)
        } label: {
            Text("Dose des aliments")
        }
    }

    /// Row de saisie de la dose globale — gros boutons `BoutonStepper` (comme
    /// les sheets lente/correction) plutôt qu'un `Stepper` natif minuscule.
    private var doseGlobaleRow: some View {
        let dose = doseGlobale ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Dose du repas")
                .font(.body)
            Text("Pour l'ensemble des glucides du repas")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                BoutonStepper(systemImage: "minus") {
                    if dose >= 0.5 { doseGlobale = dose - 0.5 }
                }
                .disabled(dose < 0.5)

                Spacer()

                Text(formate(dose) + "u")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: dose)

                Spacer()

                BoutonStepper(systemImage: "plus") {
                    if dose < 30 { doseGlobale = dose + 0.5 }
                }
                .disabled(dose >= 30)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dose globale du repas : \(formate(dose)) unités")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if dose < 30 { doseGlobale = dose + 0.5 }
            case .decrement: if dose > 0 { doseGlobale = dose - 0.5 }
            @unknown default: break
            }
        }
    }

    /// Liste des ajustements existants. Tap pour éditer, swipe pour supprimer.
    @ViewBuilder
    private var ajustementsRows: some View {
        ForEach(ajustements) { aj in
            Button {
                onEditerAjustement(aj)
            } label: {
                ligneAjustement(aj)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    ajustements.removeAll { $0.id == aj.id }
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            }
        }
    }

    private func ligneAjustement(_ aj: Ajustement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: aj.raison.icone)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(aj.raison.libelle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer()

            Text(formatSigne(aj.valeur) + "u")
                .font(.body.bold())
                .foregroundStyle(couleurAjustement(aj.valeur))
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
    }

    private var boutonAjouterAjustement: some View {
        Button(action: onAjouterAjustement) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.body)
                Text(ajustements.isEmpty ? "Ajouter un ajustement" : "Ajouter un autre ajustement")
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Gros boutons `BoutonStepper` — même pattern que `doseGlobaleRow` et
    /// que les sheets lente/correction, au lieu du `Stepper` natif minuscule.
    private var correctionHyperRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Correction hyperglycémie")
                .font(.body)
            Text("Glycémie élevée avant le repas")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                BoutonStepper(systemImage: "minus") {
                    if correctionHyper >= 0.5 { correctionHyper -= 0.5 }
                }
                .disabled(correctionHyper < 0.5)

                Spacer()

                Text("+\(formate(correctionHyper))u")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(correctionHyper > 0 ? .red : .secondary)
                    .contentTransition(.numericText())
                    // easeOut plutôt que spring : évite l'overshoot qui
                    // affiche des valeurs intermédiaires fantômes lors
                    // de taps rapides sur le stepper.
                    .animation(.easeOut(duration: 0.2), value: correctionHyper)

                Spacer()

                BoutonStepper(systemImage: "plus") {
                    if correctionHyper < 10 { correctionHyper += 0.5 }
                }
                .disabled(correctionHyper >= 10)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Correction hyperglycémie : \(formate(correctionHyper)) unités")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if correctionHyper < 10 { correctionHyper += 0.5 }
            case .decrement: if correctionHyper > 0 { correctionHyper -= 0.5 }
            @unknown default: break
            }
        }
    }

    /// Row "Total injecté" mise en avant (titre bold, valeur en title3 verte).
    private var totalInjecteRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Total injecté")
                .font(.body.bold())
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(formate(totalInjecte))
                    .font(.title3.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: totalInjecte)
                Text("u")
                    .font(.body.bold())
            }
            .foregroundStyle(.green)
        }
    }

    // MARK: - Helpers

    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }

    private func formatSigne(_ v: Double) -> String {
        let absVal = abs(v)
        let formatte = absVal == floor(absVal)
            ? String(format: "%.0f", absVal)
            : String(format: "%.1f", absVal)
        if v < 0 { return "-\(formatte)" }
        if v > 0 { return "+\(formatte)" }
        return "0"
    }

    /// Orange pour réduction (sport, hypo, IOB), rouge pour ajout (repas gras, etc.).
    private func couleurAjustement(_ valeur: Double) -> Color {
        if valeur < 0 { return .orange }
        if valeur > 0 { return .red }
        return .secondary
    }
}

// MARK: - Aperçu

#Preview("Sans ajustements") {
    @Previewable @State var ajustements: [Ajustement] = []
    @Previewable @State var correction: Double = 0
    @Previewable @State var doseGlobale: Double? = nil
    Form {
        InsulineSection(
            doseRepas: 4.5,
            ajustements: $ajustements,
            correctionHyper: $correction,
            doseGlobale: $doseGlobale,
            totalInjecte: 4.5,
            onAjouterAjustement: {},
            onEditerAjustement: { _ in }
        )
    }
    .formStyle(.grouped)
}

#Preview("Avec ajustements + correction") {
    @Previewable @State var ajustements: [Ajustement] = [
        Ajustement(raison: .sportRecent, valeur: -0.5),
        Ajustement(raison: .repasGras, valeur: 1.0),
    ]
    @Previewable @State var correction: Double = 1.5
    @Previewable @State var doseGlobale: Double? = nil
    Form {
        InsulineSection(
            doseRepas: 4.5,
            ajustements: $ajustements,
            correctionHyper: $correction,
            doseGlobale: $doseGlobale,
            totalInjecte: 6.5,
            onAjouterAjustement: {},
            onEditerAjustement: { _ in }
        )
    }
    .formStyle(.grouped)
}

#Preview("Dose globale") {
    @Previewable @State var ajustements: [Ajustement] = []
    @Previewable @State var correction: Double = 0
    @Previewable @State var doseGlobale: Double? = 6.0
    Form {
        InsulineSection(
            doseRepas: 0,
            ajustements: $ajustements,
            correctionHyper: $correction,
            doseGlobale: $doseGlobale,
            totalInjecte: 6.0,
            onAjouterAjustement: {},
            onEditerAjustement: { _ in }
        )
    }
    .formStyle(.grouped)
}
