//
//  DetailAlimentSheet.swift
//  insulog
//
//  Created by Alexandre on 28/04/2026.
//

import SwiftUI

/// Sheet de détail d'un aliment sélectionné dans la recherche.
/// Permet à l'utilisateur de configurer la quantité, la dose d'insuline,
/// une note et un flag d'approximation avant d'ajouter l'aliment au repas.
struct DetailAlimentSheet: View {

    // MARK: - Paramètres

    /// L'aliment à détailler, issu de la base CIQUAL.
    let aliment: AlimentCiqual

    /// Callback déclenché quand l'utilisateur confirme l'ajout.
    /// Reçoit une `EntreeAliment` pleinement configurée.
    let onAjouter: (EntreeAliment) -> Void

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local

    /// Quantité en grammes saisie ou glissée (5–300g).
    @State private var quantiteGrammes: Double = 100

    /// Indique si la quantité est approximative.
    @State private var quantiteApproximative: Bool = false

    /// Dose d'insuline en unités (optionnelle, 0.5–30 par pas de 0.5).
    @State private var doseInsuline: Double? = nil

    /// Note libre associée à l'entrée.
    @State private var note: String = ""

    /// Contrôle l'affichage de l'alerte de saisie manuelle de quantité.
    @State private var afficherSaisieQuantite: Bool = false

    /// Texte temporaire dans l'alerte de saisie quantité.
    @State private var saisieQuantiteTexte: String = ""

    /// Contrôle l'affichage de l'alerte de saisie manuelle de dose.
    @State private var afficherSaisieDose: Bool = false

    /// Texte temporaire dans l'alerte de saisie dose.
    @State private var saisieDoseTexte: String = ""

    /// État ouvert/fermé du DisclosureGroup des infos nutritionnelles.
    @State private var detailsOuverts: Bool = false

    // MARK: - Valeurs calculées

    /// Toutes les valeurs sont proportionnelles à la quantité saisie.
    /// Les données CIQUAL sont pour 100g, donc on applique le ratio quantiteGrammes/100.

    private var glucides: Double   { aliment.glucides   * quantiteGrammes / 100 }
    private var sucres: Double     { aliment.sucres     * quantiteGrammes / 100 }
    private var proteines: Double  { aliment.proteines  * quantiteGrammes / 100 }
    private var lipides: Double    { aliment.lipides    * quantiteGrammes / 100 }
    private var calories: Double   { aliment.calories   * quantiteGrammes / 100 }
    private var fibres: Double     { aliment.fibres     * quantiteGrammes / 100 }

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    sectionEmoji
                    sectionQuantite
                    sectionApproximatif
                    sectionGlucides
                    sectionDetailsNutritifs
                    sectionDoseInsuline
                    sectionNote
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(aliment.nom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajouter") {
                        confirmerAjout()
                    }
                    // Désactivé tant que la quantité est nulle.
                    .disabled(quantiteGrammes == 0)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Alerte saisie manuelle — quantité
        .alert("Quantité en grammes", isPresented: $afficherSaisieQuantite) {
            TextField("ex : 150", text: $saisieQuantiteTexte)
                .keyboardType(.numberPad)
            Button("OK") {
                appliquerSaisieQuantite()
            }
            Button("Annuler", role: .cancel) {
                saisieQuantiteTexte = ""
            }
        } message: {
            Text("Entrez la quantité en grammes (5–300)")
        }
        // Alerte saisie manuelle — dose insuline
        .alert("Dose d'insuline", isPresented: $afficherSaisieDose) {
            TextField("ex : 2.5", text: $saisieDoseTexte)
                .keyboardType(.decimalPad)
            Button("OK") {
                appliquerSaisieDose()
            }
            Button("Annuler", role: .cancel) {
                saisieDoseTexte = ""
            }
        } message: {
            Text("Entrez la dose en unités (0–30)")
        }
    }

    // MARK: - Actions

    /// Construit une `EntreeAliment` et appelle le callback parent, puis ferme la sheet.
    private func confirmerAjout() {
        let entree = EntreeAliment(
            aliment: aliment,
            quantiteGrammes: quantiteGrammes,
            quantiteApproximative: quantiteApproximative,
            doseInsuline: doseInsuline,
            note: note
        )
        onAjouter(entree)
        dismiss()
    }

    /// Valide et applique la saisie manuelle de quantité.
    private func appliquerSaisieQuantite() {
        let texteNormalise = saisieQuantiteTexte.replacingOccurrences(of: ",", with: ".")
        if let valeur = Double(texteNormalise), valeur > 0 {
            withAnimation(.spring(response: 0.3)) {
                quantiteGrammes = max(5, min(300, valeur))
            }
        }
        saisieQuantiteTexte = ""
    }

    /// Valide et applique la saisie manuelle de dose d'insuline.
    private func appliquerSaisieDose() {
        let texteNormalise = saisieDoseTexte.replacingOccurrences(of: ",", with: ".")
        if let valeur = Double(texteNormalise), valeur > 0 {
            doseInsuline = min(30, valeur)
        } else {
            doseInsuline = nil
        }
        saisieDoseTexte = ""
    }

    // MARK: - Sections

    /// Section 1 : emoji de l'aliment (ou SF Symbol de fallback).
    private var sectionEmoji: some View {
        Group {
            if let emoji = aliment.emoji {
                Text(emoji)
                    .font(.system(size: 80))
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// Section 2 : slider de quantité avec saisie clavier au tap.
    private var sectionQuantite: some View {
        VStack(spacing: 12) {
            // Tap sur la valeur → alerte de saisie manuelle.
            Button {
                saisieQuantiteTexte = String(Int(quantiteGrammes))
                afficherSaisieQuantite = true
            } label: {
                VStack(spacing: 2) {
                    // Préfixe "≈" si quantité approximative + couleur orange.
                    Text(quantiteApproximative ? "≈\(Int(quantiteGrammes))" : "\(Int(quantiteGrammes))")
                        .font(.title.bold())
                        .foregroundStyle(quantiteApproximative ? Color.orange : Color.primary)
                        .animation(.easeInOut(duration: 0.2), value: quantiteApproximative)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: quantiteGrammes)
                    Text("grammes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Slider 5–300g par pas de 1 gramme.
            Slider(value: $quantiteGrammes, in: 5...300, step: 1)
                .tint(quantiteApproximative ? .orange : .accentColor)
                .animation(.easeInOut(duration: 0.2), value: quantiteApproximative)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Section 3 : toggle "Quantité approximative" avec fond animé.
    private var sectionApproximatif: some View {
        Toggle(isOn: $quantiteApproximative.animation(.spring(response: 0.4, dampingFraction: 0.8))) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quantité approximative")
                    .font(.body.bold())
                Text("Je ne suis pas sûr de la quantité exacte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        // Le fond passe à orange translucide quand le toggle est activé.
        .background(
            quantiteApproximative
                ? Color.orange.opacity(0.15)
                : Color(.secondarySystemBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: quantiteApproximative)
    }

    /// Section 4 : carte glucides principale avec macro-nutriments.
    private var sectionGlucides: some View {
        VStack(spacing: 16) {

            // Valeur glucides principale — mise en avant avec grande typographie.
            VStack(spacing: 4) {
                Text("Glucides")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", glucides))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: glucides)
                    Text("g")
                        .font(.title3)
                        .foregroundStyle(.green)
                }

                Text(String(format: "dont sucres : %.1fg", sucres))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: sucres)
            }

            Divider()

            // Trois colonnes : protéines, lipides, calories.
            HStack {
                colonneNutriment(label: "Protéines", valeur: proteines, unite: "g")
                Spacer()
                colonneNutriment(label: "Lipides", valeur: lipides, unite: "g")
                Spacer()
                colonneNutriment(label: "Calories", valeur: calories, unite: "kcal")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Section 5 : informations nutritionnelles secondaires (fibres, etc.).
    private var sectionDetailsNutritifs: some View {
        DisclosureGroup("Plus d'infos nutritionnelles", isExpanded: $detailsOuverts) {
            VStack(spacing: 10) {
                ligneNutriment(label: "Fibres", valeur: fibres, unite: "g")
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Section 6 : stepper visuel pour la dose d'insuline.
    private var sectionDoseInsuline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dose d'insuline (unités)")
                .font(.body)

            HStack(spacing: 0) {
                // Bouton moins — désactivé si pas de dose saisie.
                boutonStepper(systemImage: "minus") {
                    let actuelle = doseInsuline ?? 0
                    let nouvelle = actuelle - 0.5
                    // En dessous de 0.5, on repasse à nil (pas de dose).
                    doseInsuline = nouvelle < 0.5 ? nil : nouvelle
                }
                .disabled((doseInsuline ?? 0) < 0.5)

                Spacer()

                // Valeur centrale — tap pour saisie précise.
                Button {
                    saisieDoseTexte = doseInsuline.map { String(format: "%.1f", $0) } ?? ""
                    afficherSaisieDose = true
                } label: {
                    VStack(spacing: 2) {
                        if let dose = doseInsuline {
                            Text(String(format: "%.1f", dose))
                                .font(.title.bold())
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: doseInsuline)
                            Text("unités")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            // Aucune dose saisie : tiret en gris.
                            Text("—")
                                .font(.title.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.plain)

                Spacer()

                // Bouton plus — désactivé au plafond de 30 unités.
                boutonStepper(systemImage: "plus") {
                    let nouvelle = (doseInsuline ?? 0) + 0.5
                    if nouvelle <= 30 {
                        doseInsuline = nouvelle
                    }
                }
                .disabled((doseInsuline ?? 0) >= 30)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Section 7 : champ de texte multi-lignes pour la note.
    private var sectionNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.body)

            TextField("Ajouter une note...", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .frame(minHeight: 80, alignment: .topLeading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Sous-vues réutilisables

    /// Colonne verticale label + valeur utilisée dans la carte glucides.
    @ViewBuilder
    private func colonneNutriment(label: String, valeur: Double, unite: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(String(format: "%.1f", valeur))
                    .font(.title3.bold())
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: valeur)
                Text(unite)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Ligne horizontale label–valeur utilisée dans le DisclosureGroup.
    @ViewBuilder
    private func ligneNutriment(label: String, valeur: Double, unite: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f %@", valeur, unite))
                .font(.body.bold())
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: valeur)
        }
    }

    /// Bouton rond du stepper visuel (+ ou −).
    @ViewBuilder
    private func boutonStepper(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .frame(width: 48, height: 48)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prévisualisation

#Preview {
    let aliment = AlimentCiqual(
        id: 1,
        nom: "Pomme, pulpe et peau, crue",
        calories: 52,
        glucides: 12.6,
        sucres: 10.4,
        proteines: 0.3,
        lipides: 0.2,
        fibres: 2.4,
        emoji: "🍎"
    )

    DetailAlimentSheet(aliment: aliment) { entree in
        print("Ajouté : \(entree.aliment.nom) — \(entree.quantiteGrammes)g")
    }
}
