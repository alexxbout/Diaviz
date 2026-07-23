//
//  SheetInsulineLente.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Marques d'insuline lente couramment prescrites en France.
/// Liste finie pour limiter les fautes de frappe ; l'option "Autre"
/// laisse la porte ouverte aux cas non prévus.
enum MarqueInsulineLente: String, CaseIterable, Identifiable {
    case lantus   = "Lantus"
    case tresiba  = "Tresiba"
    case toujeo   = "Toujeo"
    case levemir  = "Levemir"
    case autre    = "Autre"

    var id: String { rawValue }
}

/// Sheet d'enregistrement d'une injection d'insuline lente.
///
/// Plein écran (`.large`) avec dragIndicator. Le formulaire suit le
/// pattern grouped-form du reste de l'app, et expose le sélecteur de
/// site d'injection comme une row tappable qui ouvre `SiteInjectionPicker`.
struct SheetInsulineLente: View {

    // MARK: - Paramètres

    /// Injection existante en mode édition, ou `nil` en mode création.
    let injectionExistante: Injection?

    /// Zone de la dernière injection rapide enregistrée — sert au warning
    /// du `SiteInjectionPicker` (rotation des sites). Mockée par le parent.
    let derniereZoneLente: ZoneInjection?

    /// Callback de validation. Le parent persiste l'injection et ferme
    /// la sheet.
    let onValider: (Injection) -> Void

    // MARK: - Init

    init(
        injectionExistante: Injection? = nil,
        derniereZoneLente: ZoneInjection? = nil,
        doseParDefaut: Double? = nil,
        nomMedicamentParDefaut: String? = nil,
        onValider: @escaping (Injection) -> Void
    ) {
        self.injectionExistante = injectionExistante
        self.derniereZoneLente = derniereZoneLente
        self.onValider = onValider

        // Pré-remplissage : en édition on reprend l'injection ; en création
        // on prérempli la dose avec la **dernière dose enregistrée**
        // (`doseParDefaut`, fallback 18) et la marque avec le **type du
        // profil** (`nomMedicamentParDefaut`) — l'utilisateur n'a plus à les
        // ressaisir à chaque fois.
        _dose = State(initialValue: injectionExistante?.dose ?? doseParDefaut ?? 18)
        _heure = State(initialValue: injectionExistante?.heure ?? Date())
        _marque = State(initialValue: Self.marquePour(injectionExistante?.nomMedicament ?? nomMedicamentParDefaut))
        _marqueAutre = State(initialValue: injectionExistante?.nomMedicament ?? "")
        _site = State(initialValue: SiteInjection(
            zone: injectionExistante?.zoneInjection ?? .cuisse,
            cote: injectionExistante?.coteInjection ?? .gauche
        ))
        _note = State(initialValue: injectionExistante?.note ?? "")
    }

    private static func marquePour(_ nom: String?) -> MarqueInsulineLente {
        guard let nom else { return .lantus }
        return MarqueInsulineLente(rawValue: nom) ?? .autre
    }

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local

    @State private var dose: Double
    @State private var heure: Date
    @State private var marque: MarqueInsulineLente
    @State private var marqueAutre: String
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
                SectionDateHeure(date: $heure)
                sectionSite
                sectionNote
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Insuline lente")
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
        // Sheet du sélecteur de site — hostée à la racine pour éviter
        // que le rebuild du Form la démonte au premier tap (bug connu
        // des `.sheet` posés sur une `Section`).
        .sheet(isPresented: $afficherSitePicker) {
            SiteInjectionPicker(
                site: $site,
                derniereZoneRapide: derniereZoneLente
            )
        }
        .alert("Dose d'insuline", isPresented: $afficherSaisieDose) {
            TextField("ex : 18", text: $saisieDoseTexte)
                .keyboardType(.decimalPad)
            Button("OK") { appliquerSaisieDose() }
            Button("Annuler", role: .cancel) { saisieDoseTexte = "" }
        } message: {
            Text("Entrez la dose en unités (0–100)")
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
                    if dose < 100 { dose += 0.5 }
                }
                .disabled(dose >= 100)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Dose : \(formate(dose)) unités")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if dose < 100 { dose += 0.5 }
                case .decrement: if dose > 0 { dose -= 0.5 }
                @unknown default: break
                }
            }
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
        guard let derniereZoneLente else { return false }
        return derniereZoneLente == site.zone
    }

    private var nomMedicamentEffectif: String? {
        switch marque {
        case .autre:
            let trim = marqueAutre.trimmingCharacters(in: .whitespacesAndNewlines)
            return trim.isEmpty ? nil : trim
        default:
            return marque.rawValue
        }
    }

    // MARK: - Actions

    private func confirmer() {
        let injection = Injection(
            id: injectionExistante?.id ?? UUID(),
            type: .lente,
            dose: dose,
            heure: heure,
            zoneInjection: site.zone,
            coteInjection: site.cote,
            note: note.isEmpty ? nil : note,
            glycemieAuMoment: nil,
            repasAssocieId: nil,
            nomMedicament: nomMedicamentEffectif,
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
                dose = min(100, valeur)
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
    SheetInsulineLente(
        derniereZoneLente: .ventre,
        onValider: { _ in }
    )
}

#Preview("Édition") {
    let inj = Injection(
        type: .lente, dose: 22,
        heure: Date(),
        zoneInjection: .cuisse, coteInjection: .gauche,
        note: "Stylo neuf",
        nomMedicament: "Lantus"
    )
    return SheetInsulineLente(
        injectionExistante: inj,
        derniereZoneLente: .cuisse,
        onValider: { _ in }
    )
}
