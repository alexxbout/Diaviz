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
        // Pré-remplissage des @State quand on édite. En ajout, la quantité
        // reprend celle utilisée la dernière fois pour cet aliment (une
        // portion varie peu d'un repas à l'autre), et retombe sur 100g pour
        // un aliment jamais enregistré.
        let quantiteInitiale = entreeExistante?.quantiteGrammes
            ?? AlimentsRecentsService.shared.derniereQuantite(aliment)
            ?? 100
        _quantiteGrammes = State(initialValue: quantiteInitiale)
        _quantiteApproximative = State(initialValue: entreeExistante?.quantiteApproximative ?? false)
        _doseInsuline = State(initialValue: entreeExistante?.doseInsuline)
        _note = State(initialValue: entreeExistante?.note ?? "")
        _resucrage = State(initialValue: entreeExistante?.resucrage ?? false)

        let taillePortion = AlimentsRecentsService.shared.tailleDePortion(aliment)
        _tailleDePortion = State(initialValue: taillePortion)
        _modeQuantite = State(
            initialValue: entreeExistante?.modeQuantite
                ?? AlimentsRecentsService.shared.dernierMode(aliment)
        )
        // Nombre de portions dérivé de la quantité courante — au 0.5 près,
        // pour que la reprise en mode Portions retombe sur un compte rond.
        if let taillePortion, taillePortion > 0 {
            _nombrePortions = State(initialValue: (quantiteInitiale / taillePortion * 2).rounded() / 2)
        } else {
            _nombrePortions = State(initialValue: 1)
        }
    }

    /// Vrai en mode édition (l'aliment fait déjà partie d'un repas).
    private var enEdition: Bool { entreeExistante != nil }

    /// Id CIQUAL de l'aliment, `nil` pour un produit OFF — seuls les
    /// aliments CIQUAL sont renommables (référentiel générique, contrairement
    /// à un produit OFF déjà nommé par son propre emballage/marque).
    private var idCiqual: Int? {
        if case .ciqual(let a) = aliment { return a.id }
        return nil
    }

    /// Nom d'origine si cet aliment a un nom personnalisé actif, `nil` sinon.
    private var nomOriginalSiRenomme: String? {
        guard case .ciqual(let a) = aliment,
              NomsPersonnalisesService.shared.nomPersonnalise(pour: a.id) != nil else { return nil }
        return a.nom
    }

    /// Emoji d'origine si cet aliment a un emoji personnalisé actif, `nil` sinon.
    private var emojiOriginalSiPersonnalise: String? {
        guard case .ciqual(let a) = aliment,
              NomsPersonnalisesService.shared.emojiPersonnalise(pour: a.id) != nil else { return nil }
        return a.emoji
    }

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

    /// Mode de saisie courant (grammes ou portions) — `quantiteGrammes`
    /// reste la seule source de vérité pour les calculs nutritionnels,
    /// quel que soit le mode affiché.
    @State private var modeQuantite: ModeQuantiteAliment
    /// Taille (grammes) d'une portion pour cet aliment, `nil` tant que non
    /// définie — le mode Portions propose alors de la définir.
    @State private var tailleDePortion: Double?
    /// Nombre de portions affiché (pas de 0.5).
    @State private var nombrePortions: Double

    @State private var afficherDefinitionPortion: Bool = false
    @State private var saisieTaillePortionTexte: String = ""

    @State private var afficherRenommage: Bool = false
    @State private var saisieRenommageTexte: String = ""

    @State private var afficherChangementEmoji: Bool = false
    @State private var saisieEmojiTexte: String = ""

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
        // Alerte — définition (ou redéfinition) de la taille d'une portion
        .alert("Taille d'une portion", isPresented: $afficherDefinitionPortion) {
            TextField("ex : 130", text: $saisieTaillePortionTexte)
                .keyboardType(.numberPad)
            Button("OK") { appliquerDefinitionPortion() }
            Button("Annuler", role: .cancel) { saisieTaillePortionTexte = "" }
        } message: {
            Text("Poids en grammes d'une portion de cet aliment — mémorisé pour la prochaine fois")
        }
        // Alerte — renommage (CIQUAL uniquement)
        .alert("Renommer l'aliment", isPresented: $afficherRenommage) {
            TextField("Nom", text: $saisieRenommageTexte)
            Button("OK") { appliquerRenommage() }
            if nomOriginalSiRenomme != nil {
                Button("Restaurer le nom d'origine") {
                    if let idCiqual { NomsPersonnalisesService.shared.restaurerNom(idCiqual) }
                    saisieRenommageTexte = ""
                }
            }
            Button("Annuler", role: .cancel) { saisieRenommageTexte = "" }
        } message: {
            Text("Visible partout où cet aliment apparaît. Les repas déjà enregistrés gardent leur nom d'origine.")
        }
        // Alerte — changement d'emoji (CIQUAL uniquement)
        .alert("Changer l'emoji", isPresented: $afficherChangementEmoji) {
            TextField("Emoji", text: $saisieEmojiTexte)
            Button("OK") { appliquerChangementEmoji() }
            if emojiOriginalSiPersonnalise != nil {
                Button("Restaurer l'emoji d'origine") {
                    if let idCiqual { NomsPersonnalisesService.shared.restaurerEmoji(idCiqual) }
                    saisieEmojiTexte = ""
                }
            }
            Button("Annuler", role: .cancel) { saisieEmojiTexte = "" }
        } message: {
            Text("Visible partout où cet aliment apparaît.")
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
            copie.modeQuantite = modeQuantite
            copie.quantiteApproximative = quantiteApproximative
            copie.doseInsuline = doseInsuline
            copie.note = note
            copie.resucrage = resucrage
            entree = copie
        } else {
            entree = EntreeAliment(
                aliment: aliment,
                quantiteGrammes: quantiteGrammes,
                modeQuantite: modeQuantite,
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

    private func appliquerDefinitionPortion() {
        let texte = saisieTaillePortionTexte.replacingOccurrences(of: ",", with: ".")
        if let valeur = Double(texte), valeur > 0 {
            let taille = max(1, min(2000, valeur))
            withAnimation(.spring(response: 0.3)) {
                tailleDePortion = taille
                nombrePortions = 1
                quantiteGrammes = taille
            }
            AlimentsRecentsService.shared.definirTailleDePortion(aliment, grammes: taille)
        }
        saisieTaillePortionTexte = ""
    }

    private func appliquerRenommage() {
        defer { saisieRenommageTexte = "" }
        guard let idCiqual else { return }
        NomsPersonnalisesService.shared.renommer(idCiqual, en: saisieRenommageTexte)
    }

    private func appliquerChangementEmoji() {
        defer { saisieEmojiTexte = "" }
        guard let idCiqual else { return }
        NomsPersonnalisesService.shared.changerEmoji(idCiqual, en: saisieEmojiTexte)
    }

    /// Binding présenté au `StepperDose` — répercute chaque changement de
    /// portions sur `quantiteGrammes`, seule source de vérité nutritionnelle.
    private var bindingNombrePortions: Binding<Double> {
        Binding(
            get: { nombrePortions },
            set: { nouvelle in
                guard let taille = tailleDePortion else { return }
                nombrePortions = nouvelle
                quantiteGrammes = nouvelle * taille
            }
        )
    }

    // MARK: - En-tête

    /// Emoji + nom de l'aliment, centré, affiché avant les sections.
    private var entete: some View {
        VStack(spacing: 8) {
            // Emoji, photo du produit (OFF) ou SF Symbol de fallback.
            // Personnalisable uniquement côté CIQUAL, même geste que le nom.
            Group {
                if let idCiqual, let emoji = aliment.emoji {
                    Button {
                        saisieEmojiTexte = emoji
                        afficherChangementEmoji = true
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Text(emoji)
                                .font(.system(size: 80))
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.secondary, Color(.tertiarySystemFill))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Modifier l'emoji")
                } else if let emoji = aliment.emoji {
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

            // Nom complet de l'aliment, sans troncature. Renommable
            // uniquement côté CIQUAL — les produits OFF ont déjà un nom +
            // marque propres au produit scanné.
            if let idCiqual {
                Button {
                    saisieRenommageTexte = aliment.nom
                    afficherRenommage = true
                } label: {
                    HStack(spacing: 6) {
                        Text(aliment.nom)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                if let nomOriginal = nomOriginalSiRenomme {
                    Text("Nom d'origine : \(nomOriginal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(aliment.nom)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

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
            Picker("Mode de quantité", selection: $modeQuantite) {
                Text("Grammes").tag(ModeQuantiteAliment.grammes)
                Text("Portions").tag(ModeQuantiteAliment.portions)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if modeQuantite == .grammes {
                rowQuantite
            } else {
                rowPortions
            }

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

    /// Row portions : soit la définition de la taille (première fois pour
    /// cet aliment), soit le compte de portions une fois la taille connue.
    @ViewBuilder
    private var rowPortions: some View {
        if let taille = tailleDePortion {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("1 portion =")
                        .font(.body)
                    Spacer()
                    Button {
                        saisieTaillePortionTexte = String(Int(taille))
                        afficherDefinitionPortion = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(Int(taille))g")
                                .font(.body.bold())
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nombre de portions")
                        .font(.body)

                    StepperDose(
                        valeur: bindingNombrePortions,
                        plage: 0.5...20,
                        pas: 0.5,
                        titreSaisie: "Nombre de portions",
                        unite: ""
                    )
                }

                Text("≈ \(Int(quantiteGrammes))g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else {
            Button {
                saisieTaillePortionTexte = quantiteGrammes > 0 ? String(Int(quantiteGrammes)) : ""
                afficherDefinitionPortion = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Définir une portion")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("Poids d'une portion, réutilisé la prochaine fois")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
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
                // « — » plutôt que « 0.0 » quand OFF ne renseigne aucune
                // énergie : un zéro se lirait comme une valeur mesurée.
                colonneNutriment(
                    label: "Calories",
                    valeur: aliment.caloriesRenseignees ? calories : nil,
                    unite: "kcal"
                )
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

    /// Row dose — `StepperDose` partagé (même geste que la dose globale du
    /// repas, la correction et les ajustements). Dose optionnelle : revenir à
    /// 0 efface la dose (« — ») plutôt que d'afficher « 0u ».
    private var rowDose: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dose")
                .font(.body)

            StepperDose(valeur: $doseInsuline, plage: 0...30)
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
    /// `valeur` à `nil` = nutriment non renseigné par la source : la colonne
    /// affiche « — » sans unité, jamais un zéro trompeur.
    private func colonneNutriment(label: String, valeur: Double?, unite: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(valeur.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.body.bold())
                    .foregroundStyle(valeur == nil ? .secondary : .primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: valeur)
                if valeur != nil {
                    Text(unite)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

}

// MARK: - Prévisualisation

#if DEBUG
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
#endif
