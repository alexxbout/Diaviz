//
//  SheetEvenementsRepas.swift
//  diaviz
//

import SwiftUI

/// Édition des événements de vie d'un repas — « 🚘 Voiture », « 🍽️ Restaurant ».
///
/// Point d'entrée unique : ouverte aussi bien depuis le détail d'un repas
/// déjà enregistré (menu de la barre d'outils) que depuis la saisie en cours
/// (`RepasSheet`). Une seule UI pour la même donnée — deux écrans distincts
/// auraient divergé au premier ajustement.
///
/// La génération d'un libellé par Foundation Models tourne **pendant la
/// frappe**, ce qui inverse la règle historique de
/// `ReferentielContextesService.suggestions` (matching local uniquement, LLM
/// réservé au post-enregistrement). Deux garde-fous : un debounce, et aucun
/// appel quand le matching local trouve déjà quelque chose.
struct SheetEvenementsRepas: View {

    /// Événements déjà posés, édités en place. L'appelant persiste à la
    /// fermeture (« OK »), pas à chaque frappe.
    @State private var selection: [EvenementRepas]

    let onValider: ([EvenementRepas]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var texte: String = ""
    @State private var proposition: ContexteNormalise?
    @State private var genereEnCours = false
    /// Tâche de génération courante — annulée à chaque frappe pour que seule
    /// la dernière saisie produise une proposition.
    @State private var tacheGeneration: Task<Void, Never>?

    @State private var entreeEnEdition: ContexteNormalise?
    /// Édition d'un événement **détaché** du référentiel (`idReferentiel ==
    /// nil`, ex. ajouté via « Ajouter tel quel ») — renomme l'événement en
    /// place plutôt qu'une entrée partagée, `entreeEnEdition` ne convient pas
    /// puisqu'il n'y a rien à modifier côté référentiel.
    @State private var evenementDetacheEnEdition: EvenementRepas?
    @State private var confirmerToutRetirer = false

    /// Délai d'inactivité avant d'interroger le modèle. Assez long pour ne pas
    /// déclencher une génération par caractère, assez court pour que la
    /// proposition arrive avant que l'utilisateur ne se demande s'il doit
    /// valider lui-même.
    private static let delaiDebounce: Duration = .milliseconds(600)

    init(evenements: [EvenementRepas], onValider: @escaping ([EvenementRepas]) -> Void) {
        _selection = State(initialValue: evenements)
        self.onValider = onValider
    }

    private var referentiel: ReferentielContextesService { .shared }

    /// Entrées du référentiel pas encore posées sur ce repas. Filtrées par le
    /// texte en cours dès qu'il fait au moins 2 caractères, sinon toutes —
    /// pouvoir taper une entrée connue sans rien saisir reste le geste le plus
    /// fréquent.
    private var suggestionsDisponibles: [ContexteNormalise] {
        let base = texte.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            ? referentiel.suggestions(pour: texte)
            : referentiel.entrees
        return base.filter { entree in
            !selection.contains { $0.idReferentiel == entree.id }
        }
    }

    private var texteExploitable: Bool {
        texte.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                sectionSelection
                sectionSaisie
                sectionSuggestions
                sectionRetirerTout
                sectionAvertissement
            }
            .formStyle(.grouped)
            .navigationTitle("Événements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onValider(selection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $entreeEnEdition) { entree in
                SheetEditionEvenement(entree: entree) { libelle, emoji in
                    // `renommer` est un no-op silencieux si `entree.id`
                    // n'est pas encore dans le référentiel — le cas d'une
                    // proposition générée que l'utilisateur édite avant même
                    // de l'ajouter. Ne le tenter que si l'entrée existe déjà ;
                    // sinon la mise à jour de `proposition` ci-dessous suffit,
                    // `adopter(_:)` l'insérera avec le libellé corrigé au
                    // moment de l'ajout.
                    if referentiel.entrees.contains(where: { $0.id == entree.id }) {
                        referentiel.renommer(entree.id, libelle: libelle, emoji: emoji)
                    }
                    // Propage sur l'événement déjà posé, s'il y en a un : la
                    // sélection porte une copie du libellé, elle ne suit pas
                    // automatiquement le référentiel — pas besoin de
                    // réécrire `selection` ici, `affichageResolu` relit le
                    // référentiel à chaque rendu (voir `EvenementRepas`).
                    if proposition?.id == entree.id {
                        proposition = ContexteNormalise(
                            id: entree.id, libelle: libelle, emoji: emoji, variantes: entree.variantes
                        )
                    }
                }
            }
            .sheet(item: $evenementDetacheEnEdition) { evenement in
                SheetEditionEvenement(
                    entree: ContexteNormalise(
                        id: evenement.id, libelle: evenement.libelle,
                        emoji: evenement.emoji.isEmpty ? "🏷️" : evenement.emoji, variantes: []
                    )
                ) { libelle, emoji in
                    guard let idx = selection.firstIndex(where: { $0.id == evenement.id }) else { return }
                    selection[idx].libelle = libelle
                    selection[idx].emoji = emoji
                }
            }
            .confirmationDialog(
                "Retirer tous les événements ?",
                isPresented: $confirmerToutRetirer,
                titleVisibility: .visible
            ) {
                Button("Retirer", role: .destructive) { selection = [] }
            } message: {
                Text("Ce repas redeviendra éligible à l'analyse des ratios.")
            }
        }
        .onDisappear { tacheGeneration?.cancel() }
    }

    // MARK: - Sélection courante

    @ViewBuilder
    private var sectionSelection: some View {
        if selection.isEmpty {
            Section {
                Text("Aucun événement sur ce repas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Sur ce repas")
            }
        } else {
            Section {
                ForEach(selection) { evenement in
                    Button {
                        editer(evenement)
                    } label: {
                        HStack(spacing: 10) {
                            Text(emojiResolu(evenement))
                                .font(.title3)
                            Text(libelleResolu(evenement))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            selection.removeAll { $0.id == evenement.id }
                        } label: {
                            Label("Retirer", systemImage: "minus.circle")
                        }
                    }
                    .accessibilityAction(named: "Retirer") {
                        selection.removeAll { $0.id == evenement.id }
                    }
                }
            } header: {
                Text("Sur ce repas")
            } footer: {
                Text("Renommer une entrée déjà connue du référentiel met aussi à jour les autres repas qui la portent.")
            }
        }
    }

    // MARK: - Saisie + proposition générée

    private var sectionSaisie: some View {
        Section {
            TextField("Ex. je prends la voiture", text: $texte, axis: .vertical)
                .lineLimit(1...3)
                .onChange(of: texte) { _, nouveau in
                    planifierGeneration(pour: nouveau)
                }

            if genereEnCours {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Recherche d'un libellé…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let proposition {
                lignePropositon(proposition)
            }

            // Repli quand le modèle n'a rien produit : on garde la possibilité
            // d'ajouter le texte tel quel, sinon une saisie serait perdue dès
            // que Foundation Models est indisponible.
            if texteExploitable && proposition == nil && !genereEnCours {
                Button {
                    ajouterTexteBrut()
                } label: {
                    Label("Ajouter « \(texte.trimmingCharacters(in: .whitespacesAndNewlines)) »", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Ajouter")
        } footer: {
            Text("Le libellé est proposé par le modèle de l'appareil. Rien n'est envoyé sur Internet.")
        }
    }

    private func lignePropositon(_ entree: ContexteNormalise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(entree.emoji)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entree.libelle)
                        .font(.body)
                    Text(estDejaConnue(entree) ? "déjà dans vos événements" : "proposition")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Ajouter") { ajouter(entree) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            Button {
                entreeEnEdition = entree
            } label: {
                Label("Modifier le libellé ou l'emoji", systemImage: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
    }

    /// Route l'édition d'un événement déjà posé : vers le référentiel s'il y
    /// est rattaché (le renommage profite alors à tous les repas qui portent
    /// la même entrée), sinon vers une édition locale à cet événement seul.
    private func editer(_ evenement: EvenementRepas) {
        if let idReferentiel = evenement.idReferentiel,
           let entree = referentiel.entrees.first(where: { $0.id == idReferentiel }) {
            entreeEnEdition = entree
        } else {
            evenementDetacheEnEdition = evenement
        }
    }

    /// Émoji résolu depuis le référentiel courant si l'événement y est
    /// rattaché, sinon celui stocké sur l'événement — même logique que
    /// `EvenementRepas.affichageResolu`, séparée ici pour ne pas recomposer
    /// « emoji + libellé » en une seule chaîne dans la row.
    private func emojiResolu(_ evenement: EvenementRepas) -> String {
        guard let idReferentiel = evenement.idReferentiel,
              let entree = referentiel.entrees.first(where: { $0.id == idReferentiel })
        else { return evenement.emoji.isEmpty ? "🏷️" : evenement.emoji }
        return entree.emoji
    }

    private func libelleResolu(_ evenement: EvenementRepas) -> String {
        guard let idReferentiel = evenement.idReferentiel,
              let entree = referentiel.entrees.first(where: { $0.id == idReferentiel })
        else { return evenement.libelle }
        return entree.libelle
    }

    private func estDejaConnue(_ entree: ContexteNormalise) -> Bool {
        referentiel.entrees.contains { $0.id == entree.id }
    }

    // MARK: - Suggestions du référentiel

    @ViewBuilder
    private var sectionSuggestions: some View {
        if !suggestionsDisponibles.isEmpty {
            Section {
                ForEach(suggestionsDisponibles) { entree in
                    HStack(spacing: 10) {
                        Button {
                            ajouter(entree)
                        } label: {
                            HStack(spacing: 10) {
                                Text(entree.emoji).font(.title3)
                                Text(entree.libelle)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            entreeEnEdition = entree
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Modifier \(entree.libelle)")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            referentiel.supprimer(entree.id)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Déjà utilisés")
            } footer: {
                Text("Balayer vers la gauche retire un événement de cette liste. Les repas déjà tagués le restent.")
            }
        }
    }

    @ViewBuilder
    private var sectionRetirerTout: some View {
        if !selection.isEmpty {
            Section {
                Button("Retirer tous les événements", role: .destructive) {
                    confirmerToutRetirer = true
                }
            }
        }
    }

    private var sectionAvertissement: some View {
        Section {
            Label {
                Text("Un repas portant un événement est exclu de l'analyse des ratios. Retirer tous ses événements l'y remet.")
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .foregroundStyle(.orange)
        }
    }

    // MARK: - Actions

    private func ajouter(_ entree: ContexteNormalise) {
        let brut = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        let adoptee = referentiel.adopter(entree, texteBrut: brut.isEmpty ? nil : brut)
        selection.append(EvenementRepas(depuis: adoptee, texteBrut: brut.isEmpty ? nil : brut))
        reinitialiserSaisie()
    }

    /// Ajoute le texte tel quel, sans passer par le référentiel : l'événement
    /// porte alors `idReferentiel == nil` et ne bénéficiera d'aucune
    /// convergence future — c'est le prix d'un ajout hors modèle.
    private func ajouterTexteBrut() {
        let brut = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brut.isEmpty else { return }
        selection.append(EvenementRepas(libelle: brut, emoji: "🏷️", texteBrut: brut))
        reinitialiserSaisie()
    }

    private func reinitialiserSaisie() {
        tacheGeneration?.cancel()
        tacheGeneration = nil
        texte = ""
        proposition = nil
        genereEnCours = false
    }

    /// Debounce + court-circuit local : la génération n'est lancée que si rien
    /// dans le référentiel ne correspond déjà au texte.
    private func planifierGeneration(pour nouveau: String) {
        tacheGeneration?.cancel()
        proposition = nil

        let propre = nouveau.trimmingCharacters(in: .whitespacesAndNewlines)
        guard propre.count >= 2 else {
            genereEnCours = false
            return
        }
        if let locale = referentiel.suggestions(pour: propre).first {
            genereEnCours = false
            proposition = locale
            return
        }

        genereEnCours = true
        tacheGeneration = Task {
            try? await Task.sleep(for: Self.delaiDebounce)
            guard !Task.isCancelled else { return }
            let resultat = await referentiel.proposer(texte: propre)
            guard !Task.isCancelled else { return }
            proposition = resultat
            genereEnCours = false
        }
    }
}

// MARK: - Édition d'une entrée

/// Renommage d'une entrée du référentiel — libellé et emoji.
private struct SheetEditionEvenement: View {
    let entree: ContexteNormalise
    let onValider: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var libelle: String
    @State private var emoji: String

    init(entree: ContexteNormalise, onValider: @escaping (String, String) -> Void) {
        self.entree = entree
        self.onValider = onValider
        _libelle = State(initialValue: entree.libelle)
        _emoji = State(initialValue: entree.emoji)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Emoji") {
                    TextField("🏷️", text: $emoji)
                }
                Section("Libellé") {
                    TextField("Ex. Restaurant", text: $libelle)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onValider(libelle, emoji)
                        dismiss()
                    }
                    .disabled(libelle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Avec événements") {
    SheetEvenementsRepas(evenements: [
        EvenementRepas(libelle: "Voiture", emoji: "🚘"),
        EvenementRepas(libelle: "Stress boulot", emoji: "😰"),
    ]) { _ in }
}

#Preview("Vide") {
    SheetEvenementsRepas(evenements: []) { _ in }
}
#endif
