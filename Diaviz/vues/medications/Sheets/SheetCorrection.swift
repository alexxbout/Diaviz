//
//  SheetCorrection.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Sheet d'enregistrement d'une injection de correction (rapide hors repas).
///
/// Champs :
/// - dose (stepper + saisie clavier)
/// - glycémie avant le repas (optionnelle, capillaire — saisie manuelle
///   parce que le CGM Dexcom UE a un délai de 3h)
/// - heure (DatePicker)
/// - site d'injection (réutilise `SiteInjectionPicker`)
/// - note (optionnelle)
struct SheetCorrection: View {

    // MARK: - Paramètres

    let injectionExistante: Injection?
    let derniereZoneRapide: ZoneInjection?
    let onValider: (Injection) -> Void

    // MARK: - Init

    init(
        injectionExistante: Injection? = nil,
        derniereZoneRapide: ZoneInjection? = nil,
        onValider: @escaping (Injection) -> Void
    ) {
        self.injectionExistante = injectionExistante
        self.derniereZoneRapide = derniereZoneRapide
        self.onValider = onValider

        _dose = State(initialValue: injectionExistante?.dose ?? 1.0)
        _heure = State(initialValue: injectionExistante?.heure ?? Date())
        _glycemieTexte = State(initialValue: injectionExistante?.glycemieAuMoment.map { String(Int($0)) } ?? "")
        _site = State(initialValue: SiteInjection(
            zone: injectionExistante?.zoneInjection ?? .ventre,
            cote: injectionExistante?.coteInjection ?? .gauche
        ))
        _note = State(initialValue: injectionExistante?.note ?? "")
    }

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local

    @State private var dose: Double
    @State private var heure: Date
    @State private var glycemieTexte: String
    @State private var site: SiteInjection
    @State private var note: String

    @State private var afficherSaisieDose: Bool = false
    @State private var saisieDoseTexte: String = ""

    @State private var afficherSitePicker: Bool = false

    /// Trigger du retour haptique de succès à l'enregistrement.
    @State private var triggerHaptique: Int = 0

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            Form {
                sectionDose
                sectionGlycemie
                sectionHeure
                sectionSite
                sectionNote
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { confirmer() }
                        .disabled(dose <= 0)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .sensoryFeedback(.success, trigger: triggerHaptique)
        .sheet(isPresented: $afficherSitePicker) {
            SiteInjectionPicker(
                site: $site,
                derniereZoneRapide: derniereZoneRapide
            )
        }
        .alert("Dose d'insuline", isPresented: $afficherSaisieDose) {
            TextField("ex : 1.5", text: $saisieDoseTexte)
                .keyboardType(.decimalPad)
            Button("OK") { appliquerSaisieDose() }
            Button("Annuler", role: .cancel) { saisieDoseTexte = "" }
        } message: {
            Text("Entrez la dose en unités (0–30)")
        }
    }

    // MARK: - Sections

    private var sectionDose: some View {
        Section("Dose") {
            HStack {
                BoutonStepper(systemImage: "minus") {
                    if dose >= 0.5 { dose -= 0.5 }
                }
                .disabled(dose < 0.5)

                Spacer()

                Button {
                    saisieDoseTexte = formate(dose)
                    afficherSaisieDose = true
                } label: {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(formate(dose))
                            .font(.title2.bold())
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: dose)
                        Text("u")
                            .font(.body.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                BoutonStepper(systemImage: "plus") {
                    if dose < 30 { dose += 0.5 }
                }
                .disabled(dose >= 30)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Dose : \(formate(dose)) unités")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if dose < 30 { dose += 0.5 }
                case .decrement: if dose > 0 { dose -= 0.5 }
                @unknown default: break
                }
            }
        }
    }

    private var sectionGlycemie: some View {
        Section {
            HStack {
                TextField("Optionnel", text: $glycemieTexte)
                    .keyboardType(.numberPad)
                Text("mg/dL")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Glycémie avant")
        } footer: {
            Text("Le CGM a un délai de 3h, vous pouvez saisir la valeur capillaire actuelle.")
        }
    }

    private var sectionHeure: some View {
        Section("Heure") {
            DatePicker(
                "Heure",
                selection: $heure,
                displayedComponents: [.hourAndMinute]
            )
        }
    }

    private var sectionSite: some View {
        Section("Site d'injection") {
            Button {
                afficherSitePicker = true
            } label: {
                HStack {
                    Text(site.libelle)
                        .foregroundStyle(.primary)
                    Spacer()
                    if memeZoneQueDerniere {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Site d'injection : \(site.libelle)")
            .accessibilityHint("Touchez deux fois pour changer de site")
        }
    }

    private var sectionNote: some View {
        Section("Note") {
            TextField("Optionnel", text: $note, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    // MARK: - Calculs

    private var memeZoneQueDerniere: Bool {
        guard let derniereZoneRapide else { return false }
        return derniereZoneRapide == site.zone
    }

    private var glycemieDouble: Double? {
        let trim = glycemieTexte.trimmingCharacters(in: .whitespaces)
        return trim.isEmpty ? nil : Double(trim)
    }

    // MARK: - Actions

    private func confirmer() {
        let injection = Injection(
            id: injectionExistante?.id ?? UUID(),
            type: .rapideCorrection,
            dose: dose,
            heure: heure,
            zoneInjection: site.zone,
            coteInjection: site.cote,
            note: note.isEmpty ? nil : note,
            glycemieAuMoment: glycemieDouble,
            repasAssocieId: nil,
            nomMedicament: nil,
            labelRepas: nil,
            emojiRepas: nil
        )
        triggerHaptique += 1
        onValider(injection)
        dismiss()
    }

    private func appliquerSaisieDose() {
        let texte = saisieDoseTexte.replacingOccurrences(of: ",", with: ".")
        if let valeur = Double(texte), valeur >= 0 {
            withAnimation(.easeOut(duration: 0.2)) {
                dose = min(30, valeur)
            }
        }
        saisieDoseTexte = ""
    }

    // MARK: - Helpers

    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }
}

// MARK: - Aperçu

#Preview("Création") {
    SheetCorrection(
        derniereZoneRapide: .ventre,
        onValider: { _ in }
    )
}

#Preview("Édition avec glycémie") {
    let inj = Injection(
        type: .rapideCorrection, dose: 1.5,
        heure: Date(),
        zoneInjection: .bras, coteInjection: .droite,
        glycemieAuMoment: 165
    )
    return SheetCorrection(
        injectionExistante: inj,
        derniereZoneRapide: .bras,
        onValider: { _ in }
    )
}
