//
//  SheetNouvelleActivite.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Sheet de création (ou édition) d'une activité sportive.
///
/// Sections :
/// - **Type de sport** : grille 4×2 d'emojis tappables (pas de Picker)
/// - **Heure de début** : DatePicker compact date+heure
/// - **Durée** : stepper visuel + saisie clavier sur tap de la valeur
/// - **Intensité** : 3 cards radio empilées (pas de segmented control)
/// - **Glucides pré-sport** : champ optionnel avec suffixe « g »
/// - **Note** : champ optionnel multilignes
///
/// La sheet ne valide rien — toutes les valeurs sauf `type` ont des
/// défauts raisonnables. Le bouton Enregistrer est désactivé tant
/// qu'aucun type n'a été choisi.
struct SheetNouvelleActivite: View {

    // MARK: - Paramètres

    let activiteExistante: ActiviteSportive?
    let onValider: (ActiviteSportive) -> Void

    // MARK: - Init

    init(
        activiteExistante: ActiviteSportive? = nil,
        onValider: @escaping (ActiviteSportive) -> Void
    ) {
        self.activiteExistante = activiteExistante
        self.onValider = onValider

        _typeSelectionne = State(initialValue: activiteExistante?.type)
        _dateDebut = State(initialValue: activiteExistante?.dateDebut ?? Date())
        _dureeMinutes = State(initialValue: activiteExistante?.dureeMinutes ?? 30)
        _intensite = State(initialValue: activiteExistante?.intensite ?? .moderee)
        _glucidesTexte = State(
            initialValue: activiteExistante?.glucidesPreSport.map { String(format: "%g", $0) } ?? ""
        )
        _note = State(initialValue: activiteExistante?.note ?? "")
    }

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local

    @State private var typeSelectionne: TypeSport?
    @State private var dateDebut: Date
    @State private var dureeMinutes: Int
    @State private var intensite: IntensiteSport
    @State private var glucidesTexte: String
    @State private var note: String

    @State private var afficherSaisieDuree: Bool = false
    @State private var saisieDureeTexte: String = ""

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            Form {
                sectionType
                sectionHeure
                sectionDuree
                sectionIntensite
                sectionGlucides
                sectionNote
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(activiteExistante == nil ? "Nouvelle activité" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { confirmer() }
                        .disabled(typeSelectionne == nil)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .alert("Durée", isPresented: $afficherSaisieDuree) {
            TextField("ex : 45", text: $saisieDureeTexte)
                .keyboardType(.numberPad)
            Button("OK") { appliquerSaisieDuree() }
            Button("Annuler", role: .cancel) { saisieDureeTexte = "" }
        } message: {
            Text("Entrez la durée en minutes (1–300)")
        }
    }

    // MARK: - Section type
    //
    // Grille 4×2 — chaque case combine emoji et nom du sport. Le tap
    // sélectionne avec animation spring et retour visuel via bordure
    // accent + fond teinté.

    private var sectionType: some View {
        Section {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                spacing: 12
            ) {
                ForEach(TypeSport.allCases, id: \.self) { type in
                    BoutonTypeSport(
                        type: type,
                        selectionne: typeSelectionne == type
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            typeSelectionne = type
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Type de sport")
        }
    }

    // MARK: - Section heure
    private var sectionHeure: some View {
        Section("Heure de début") {
            DatePicker(
                "Heure",
                selection: $dateDebut,
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.locale, Locale(identifier: "fr_FR"))
        }
    }

    // MARK: - Section durée
    //
    // Stepper visuel — pattern identique à `SheetCorrection`. Tap sur
    // la valeur centrale ouvre une alert avec saisie clavier numérique.
    private var sectionDuree: some View {
        Section("Durée") {
            HStack {
                BoutonStepper(systemImage: "minus") {
                    if dureeMinutes >= 5 { dureeMinutes -= 5 }
                }
                .disabled(dureeMinutes < 5)

                Spacer()

                Button {
                    saisieDureeTexte = "\(dureeMinutes)"
                    afficherSaisieDuree = true
                } label: {
                    VStack(spacing: 0) {
                        Text("\(dureeMinutes)")
                            .font(.title.bold())
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: dureeMinutes)
                        Text("minutes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                BoutonStepper(systemImage: "plus") {
                    if dureeMinutes < 300 { dureeMinutes += 5 }
                }
                .disabled(dureeMinutes >= 300)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Durée : \(dureeMinutes) minutes")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if dureeMinutes < 300 { dureeMinutes += 5 }
                case .decrement: if dureeMinutes > 1 { dureeMinutes -= 5 }
                @unknown default: break
                }
            }
        }
    }

    // MARK: - Section intensité
    //
    // Cards radio verticales — pas de Picker segmenté pour deux raisons :
    // 1. on veut afficher la description sous chaque option
    // 2. l'effet visuel "card sélectionnée" est plus parlant
    private var sectionIntensite: some View {
        Section("Intensité") {
            VStack(spacing: 8) {
                ForEach(IntensiteSport.allCases, id: \.self) { niveau in
                    CarteRadioIntensite(
                        intensite: niveau,
                        selectionnee: intensite == niveau
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            intensite = niveau
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    // MARK: - Section glucides
    private var sectionGlucides: some View {
        Section {
            HStack {
                TextField("Optionnel", text: $glucidesTexte)
                    .keyboardType(.decimalPad)
                Text("g")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Glucides pré-sport")
        } footer: {
            Text("À renseigner si vous avez pris des glucides juste avant l'activité.")
        }
    }

    // MARK: - Section note
    private var sectionNote: some View {
        Section("Note") {
            TextField("Ajouter une note...", text: $note, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    // MARK: - Calculs

    private var glucidesDouble: Double? {
        let trim = glucidesTexte
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return trim.isEmpty ? nil : Double(trim)
    }

    // MARK: - Actions

    private func confirmer() {
        guard let type = typeSelectionne else { return }
        let activite = ActiviteSportive(
            id: activiteExistante?.id ?? UUID(),
            type: type,
            dateDebut: dateDebut,
            dureeMinutes: dureeMinutes,
            intensite: intensite,
            glucidesPreSport: glucidesDouble,
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
        )
        onValider(activite)
        dismiss()
    }

    private func appliquerSaisieDuree() {
        if let valeur = Int(saisieDureeTexte), valeur >= 1 {
            withAnimation(.easeOut(duration: 0.2)) {
                dureeMinutes = min(300, valeur)
            }
        }
        saisieDureeTexte = ""
    }
}

// MARK: - Aperçu

#Preview("Création") {
    SheetNouvelleActivite(onValider: { _ in })
}

#Preview("Édition") {
    let act = ActiviteSportive(
        type: .course,
        dateDebut: Date(),
        dureeMinutes: 45,
        intensite: .moderee,
        glucidesPreSport: 15,
        note: "Footing au parc"
    )
    return SheetNouvelleActivite(activiteExistante: act, onValider: { _ in })
}
