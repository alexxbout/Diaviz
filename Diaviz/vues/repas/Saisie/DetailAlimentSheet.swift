//
//  DetailAlimentSheet.swift
//  diaviz
//
//  Created by Alexandre on 28/04/2026.
//

import SwiftUI

/// Sheet de détail d'un aliment sélectionné dans la recherche.
/// Permet à l'utilisateur de configurer la quantité, la dose d'insuline,
/// une note et un flag d'approximation avant d'ajouter l'aliment au repas.
struct DetailAlimentSheet: View {

    // MARK: - Paramètres

    let aliment: ResultatRechercheAliment

    /// Entrée pré-existante quand on est en mode édition (tap sur une row
    /// dans `RepasSheet`). nil → mode ajout (ouverture depuis la recherche).
    let entreeExistante: EntreeAliment?

    /// Callback de validation (à la fois pour l'ajout et l'édition).
    /// L'appelant décide d'append ou de remplacer dans sa liste.
    let onValider: (EntreeAliment) -> Void

    // MARK: - Init custom (pour pré-remplir l'état en mode édition)

    init(
        aliment: ResultatRechercheAliment,
        entreeExistante: EntreeAliment? = nil,
        onValider: @escaping (EntreeAliment) -> Void
    ) {
        self.aliment = aliment
        self.entreeExistante = entreeExistante
        self.onValider = onValider
        // Pré-remplissage des @State quand on édite. En ajout, on conserve
        // les valeurs par défaut historiques (100g, pas de dose, etc.).
        _quantiteGrammes = State(initialValue: entreeExistante?.quantiteGrammes ?? 100)
        _quantiteApproximative = State(initialValue: entreeExistante?.quantiteApproximative ?? false)
        _doseInsuline = State(initialValue: entreeExistante?.doseInsuline)
        _note = State(initialValue: entreeExistante?.note ?? "")
        _resucrage = State(initialValue: entreeExistante?.resucrage ?? false)
    }

    /// Vrai en mode édition (l'aliment fait déjà partie d'un repas).
    private var enEdition: Bool { entreeExistante != nil }

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local

    @State private var quantiteGrammes: Double
    @State private var quantiteApproximative: Bool
    @State private var doseInsuline: Double?
    @State private var note: String
    @State private var resucrage: Bool

    @State private var afficherSaisieQuantite: Bool = false
    @State private var saisieQuantiteTexte: String = ""
    @State private var afficherSaisieDose: Bool = false
    @State private var saisieDoseTexte: String = ""

    // MARK: - Valeurs calculées (proportionnelles à quantiteGrammes)

    private var glucides: Double  { aliment.glucides  * quantiteGrammes / 100 }
    private var sucres: Double    { aliment.sucres    * quantiteGrammes / 100 }
    private var proteines: Double { aliment.proteines * quantiteGrammes / 100 }
    private var lipides: Double   { aliment.lipides   * quantiteGrammes / 100 }
    private var calories: Double  { aliment.calories  * quantiteGrammes / 100 }

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            Form {
                // En-tête emoji + titre — fond transparent pour s'intégrer
                // naturellement au Form sans apparaître comme une row.
                Section {
                    entete
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                sectionPortion
                sectionNutrition
                sectionInsuline
                sectionNote
            }
            .formStyle(.grouped)
            // Le clavier se ferme dès qu'on commence à scroller — utile
            // notamment dans la section Note quand on saisit une note longue.
            .scrollDismissesKeyboard(.immediately)
            .sensoryFeedback(.selection, trigger: quantiteApproximative)
            // Pas de navigationTitle : le titre est dans le contenu.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(enEdition ? "Enregistrer" : "Ajouter") {
                        confirmerValidation()
                    }
                    .disabled(quantiteGrammes == 0)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Pas de Liquid Glass sur les sheets internes — fond plat aligné
        // sur le style grouped form.
        .presentationBackground(Color(.systemGroupedBackground))
        // Alerte — saisie manuelle de la quantité
        .alert("Quantité en grammes", isPresented: $afficherSaisieQuantite) {
            TextField("ex : 150", text: $saisieQuantiteTexte)
                .keyboardType(.numberPad)
            Button("OK") { appliquerSaisieQuantite() }
            Button("Annuler", role: .cancel) { saisieQuantiteTexte = "" }
        } message: {
            Text("Entrez la quantité en grammes (5–2000)")
        }
        // Alerte — saisie manuelle de la dose d'insuline
        .alert("Dose d'insuline", isPresented: $afficherSaisieDose) {
            TextField("ex : 2.5", text: $saisieDoseTexte)
                .keyboardType(.decimalPad)
            Button("OK") { appliquerSaisieDose() }
            Button("Annuler", role: .cancel) { saisieDoseTexte = "" }
        } message: {
            Text("Entrez la dose en unités (0–30)")
        }
    }

    // MARK: - Actions

    private func confirmerValidation() {
        // En mode édition, on copie l'entrée existante pour préserver son `id`
        // (UUID auto-généré qui sert d'`Identifiable`). En mode ajout, on
        // construit une nouvelle instance — un nouvel id est généré.
        let entree: EntreeAliment
        if var copie = entreeExistante {
            copie.quantiteGrammes = quantiteGrammes
            copie.quantiteApproximative = quantiteApproximative
            copie.doseInsuline = doseInsuline
            copie.note = note
            copie.resucrage = resucrage
            entree = copie
        } else {
            entree = EntreeAliment(
                aliment: aliment,
                quantiteGrammes: quantiteGrammes,
                quantiteApproximative: quantiteApproximative,
                doseInsuline: doseInsuline,
                note: note,
                resucrage: resucrage
            )
        }
        onValider(entree)
        dismiss()
    }

    private func appliquerSaisieQuantite() {
        let texte = saisieQuantiteTexte.replacingOccurrences(of: ",", with: ".")
        if let valeur = Double(texte), valeur > 0 {
            withAnimation(.spring(response: 0.3)) {
                // Plafond relevé à 2000g (portions type plat familial /
                // batch cooking) — le slider, lui, garde une plage courte
                // pour rester précis au pas de 5g, et s'étend dynamiquement
                // si la valeur saisie le dépasse (cf. `rowQuantite`).
                quantiteGrammes = max(5, min(2000, valeur))
            }
        }
        saisieQuantiteTexte = ""
    }

    private func appliquerSaisieDose() {
        let texte = saisieDoseTexte.replacingOccurrences(of: ",", with: ".")
        if let valeur = Double(texte), valeur > 0 {
            doseInsuline = min(30, valeur)
        } else {
            doseInsuline = nil
        }
        saisieDoseTexte = ""
    }

    // MARK: - En-tête

    /// Emoji + nom de l'aliment, centré, affiché avant les sections.
    private var entete: some View {
        VStack(spacing: 8) {
            // Emoji, photo du produit (OFF) ou SF Symbol de fallback
            Group {
                if let emoji = aliment.emoji {
                    Text(emoji)
                        .font(.system(size: 80))
                } else if let url = aliment.imageURL {
                    // Mode `ajuster` (pas de recadrage, contrairement aux
                    // vignettes carrées des listes) : préserve l'aspect naturel
                    // de la photo produit. `maxWidth`/`maxHeight` + `.clipped()`
                    // bornent la taille finale pour qu'elle ne chevauche jamais
                    // le titre en dessous, quel que soit le ratio de la photo.
                    ImageProduit(url: url, coinArrondi: 16, remplir: false)
                        .frame(maxWidth: 280, maxHeight: 280)
                        .clipped()
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 20)

            // Nom complet de l'aliment, sans troncature
            Text(aliment.nom)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Marque du produit (OFF uniquement)
            if let marque = aliment.marque {
                Text(marque)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Produit OFF sans glucides renseignés : signalement factuel —
            // les valeurs affichées comptent 0, à vérifier sur l'emballage.
            if !aliment.glucidesRenseignes {
                Label("Glucides non renseignés — vérifier l'emballage", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    // MARK: - Section Portion

    private var sectionPortion: some View {
        Section("Portion") {
            // Row quantité avec slider intégré
            rowQuantite

            // Row toggle approximatif — même orange que la valeur de
            // quantité quand actif (rowQuantite), pour une lecture cohérente
            // du statut "approximatif" dans toute la sheet.
            Toggle(isOn: $quantiteApproximative) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quantité approximative")
                        .font(.body)
                    Text("Je ne suis pas sûr de la quantité exacte")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.orange)

            // Row toggle resucrage — rouge : signale un usage distinct d'un
            // aliment de repas ordinaire (traitement d'une hypoglycémie).
            Toggle(isOn: $resucrage) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resucrage")
                        .font(.body)
                    Text("Pris pour traiter une hypoglycémie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.red)
        }
    }

    /// Row quantité : label + valeur tappable + slider.
    private var rowQuantite: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quantité")
                    .font(.body)

                Spacer()

                // Tap → alerte de saisie manuelle.
                // Couleur orange si approximatif, noir sinon.
                Button {
                    saisieQuantiteTexte = String(Int(quantiteGrammes))
                    afficherSaisieQuantite = true
                } label: {
                    Text(quantiteApproximative ? "≈ \(Int(quantiteGrammes))g" : "\(Int(quantiteGrammes))g")
                        .font(.body.bold())
                        .foregroundStyle(quantiteApproximative ? Color.orange : Color.primary)
                        .animation(.easeInOut(duration: 0.2), value: quantiteApproximative)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: quantiteGrammes)
                }
                .buttonStyle(.plain)
            }

            // Borne haute dynamique : 300g par défaut (pas de 5g précis pour
            // les portions courantes), étendue à la valeur courante si une
            // saisie manuelle la dépasse — sinon le slider clippait
            // silencieusement toute quantité au-delà de 300g.
            Slider(value: $quantiteGrammes, in: 5...max(300, quantiteGrammes), step: 5)
                .tint(quantiteApproximative ? .orange : .accentColor)
                .animation(.easeInOut(duration: 0.2), value: quantiteApproximative)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Section Nutrition

    private var sectionNutrition: some View {
        Section("Nutrition") {
            // Glucides + macros fusionnés en une seule row pour éviter
            // les séparateurs mal alignés entre les deux blocs.
            // alignmentGuide force le séparateur du bas à partir du bord gauche (inset 0).
            rowNutritionPrincipale
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    /// Row unique fusionnant glucides + macros séparés par un Divider.
    /// Une seule row = pas de séparateur automatique entre les deux blocs.
    private var rowNutritionPrincipale: some View {
        VStack(spacing: 12) {
            // Glucides — valeur principale mise en avant
            VStack(spacing: 4) {
                Text("Glucides")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", glucides))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: glucides)
                    Text("g")
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                }

                Text(String(format: "dont sucres : %.1fg", sucres))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: sucres)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            Divider()

            // Macros — 3 colonnes égales
            HStack {
                colonneNutriment(label: "Protéines", valeur: proteines, unite: "g")
                Spacer()
                colonneNutriment(label: "Lipides", valeur: lipides, unite: "g")
                Spacer()
                colonneNutriment(label: "Calories", valeur: calories, unite: "kcal")
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Section Insuline

    private var sectionInsuline: some View {
        Section("Insuline") {
            rowDose
        }
    }

    private var sectionNote: some View {
        Section("Note") {
            rowNote
        }
    }

    /// Row dose : stepper visuel − / valeur tappable / +.
    private var rowDose: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dose")
                .font(.body)

            HStack {
                // Bouton moins
                boutonStepper(systemImage: "minus") {
                    let actuelle = doseInsuline ?? 0
                    let nouvelle = actuelle - 0.5
                    doseInsuline = nouvelle < 0.5 ? nil : nouvelle
                }
                .disabled((doseInsuline ?? 0) < 0.5)

                Spacer()

                // Valeur centrale tappable
                Button {
                    saisieDoseTexte = doseInsuline.map { String(format: "%.1f", $0) } ?? ""
                    afficherSaisieDose = true
                } label: {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        if let dose = doseInsuline {
                            Text(String(format: "%.1f", dose))
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                                // easeOut au lieu de spring : un spring même
                                // léger overshoote, et avec
                                // `.contentTransition(.numericText())` cet
                                // overshoot affichait des valeurs
                                // intermédiaires fantômes (ex : 1.5
                                // pendant la transition 0.5 → 1.0).
                                .animation(.easeOut(duration: 0.2), value: doseInsuline)
                            Text("u")
                                .font(.body.bold())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Bouton plus
                boutonStepper(systemImage: "plus") {
                    let nouvelle = (doseInsuline ?? 0) + 0.5
                    if nouvelle <= 30 { doseInsuline = nouvelle }
                }
                .disabled((doseInsuline ?? 0) >= 30)
            }
        }
        .padding(.vertical, 4)
    }

    /// Row note : champ multilignes.
    private var rowNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.body)

            TextField("Ajouter une note...", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sous-vues réutilisables

    /// Colonne verticale label + valeur utilisée dans la row macros.
    @ViewBuilder
    private func colonneNutriment(label: String, valeur: Double, unite: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(String(format: "%.1f", valeur))
                    .font(.body.bold())
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: valeur)
                Text(unite)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Bouton carré du stepper visuel (+ ou −).
    @ViewBuilder
    private func boutonStepper(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.bold())
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

    DetailAlimentSheet(aliment: .ciqual(aliment)) { entree in
        print("Validé : \(entree.aliment.nom) — \(entree.quantiteGrammes)g")
    }
}
