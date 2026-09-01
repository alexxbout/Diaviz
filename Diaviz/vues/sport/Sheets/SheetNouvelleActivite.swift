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
/// - **Glucides pré-sport** : liste d'aliments (recherche), quantité et
///   glucides calculés par aliment ajouté
/// - **Note** : champ optionnel multilignes
///
/// La sheet ne valide rien — toutes les valeurs sauf `type` ont des
/// défauts raisonnables. Le bouton Enregistrer est désactivé tant
/// qu'aucun type n'a été choisi.
struct SheetNouvelleActivite: View {

    // MARK: - Paramètres

    let activiteExistante: ActiviteSportive?
    /// Brouillon de pré-remplissage (ex. séance chronométrée qui vient de se
    /// terminer). Distinct d'`activiteExistante` : ne signifie pas « édition »
    /// (titre reste « Nouvelle activité », un nouvel `id` est généré à la
    /// confirmation), mais force le mode manuel avec les champs pré-remplis.
    let preremplissage: ActiviteSportive?
    let onValider: (ActiviteSportive) -> Void
    /// Démarre une séance chronométrée en direct pour le type choisi. Fourni
    /// uniquement en création — absent en édition. Sa présence active le
    /// sélecteur de mode « Chrono en direct / Saisie manuelle ».
    let onDemarrer: ((TypeSport, StructureEffort?) -> Void)?

    /// Enregistre les glucides pré-sport sous forme de resucrages
    /// « préventif maintien ». Les glucides pris avant une séance visent
    /// exactement le même objectif que ceux pris pendant — les garder dans un
    /// champ séparé de l'activité en faisait la seule prise que l'analyse ne
    /// pouvait jamais juger, faute d'horodatage. `nil` dans les previews.
    var onCreerResucrages: (([Resucrage]) -> Void)? = nil

    /// `true` en édition d'une activité existante — le titre passe à
    /// « Modifier » et l'`id` d'origine est réutilisé (upsert).
    private let estEdition: Bool

    // MARK: - Init

    init(
        activiteExistante: ActiviteSportive? = nil,
        preremplissage: ActiviteSportive? = nil,
        onValider: @escaping (ActiviteSportive) -> Void,
        onDemarrer: ((TypeSport, StructureEffort?) -> Void)? = nil,
        onCreerResucrages: (([Resucrage]) -> Void)? = nil
    ) {
        self.activiteExistante = activiteExistante
        self.preremplissage = preremplissage
        self.onValider = onValider
        self.onDemarrer = onDemarrer
        self.onCreerResucrages = onCreerResucrages
        self.estEdition = activiteExistante != nil

        let source = activiteExistante ?? preremplissage
        _typeSelectionne = State(initialValue: source?.type)
        _dateDebut = State(initialValue: source?.dateDebut ?? Date())
        _dureeMinutes = State(initialValue: source?.dureeMinutes ?? 30)
        _intensite = State(initialValue: source?.intensite ?? .moderee)
        _structureEffort = State(initialValue: source?.structureEffort)
        _alimentsPreSport = State(initialValue: source?.alimentsPreSport ?? [])
        _note = State(initialValue: source?.note ?? "")

        // Mode initial : « Chrono en direct » par défaut en création pure,
        // « Saisie manuelle » dès qu'on édite ou qu'on pré-remplit un brouillon.
        let modeInitial: ModeCreation =
            (activiteExistante == nil && preremplissage == nil && onDemarrer != nil) ? .direct : .manuel
        _mode = State(initialValue: modeInitial)
    }

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local

    @State private var typeSelectionne: TypeSport?
    @State private var dateDebut: Date
    @State private var dureeMinutes: Int
    @State private var intensite: IntensiteSport
    @State private var structureEffort: StructureEffort?
    @State private var alimentsPreSport: [Aliment]
    @State private var note: String
    @State private var mode: ModeCreation

    @State private var afficherSaisieDuree: Bool = false
    @State private var saisieDureeTexte: String = ""
    @State private var afficherRechercheAliment: Bool = false

    /// Mode de création : chronomètre en direct vs saisie rétrospective.
    enum ModeCreation: Hashable { case direct, manuel }

    /// Le sélecteur de mode n'a de sens qu'en création pure avec un handler
    /// de démarrage — pas en édition ni en pré-remplissage d'un brouillon.
    private var peutBasculerMode: Bool {
        !estEdition && preremplissage == nil && onDemarrer != nil
    }

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            Form {
                if peutBasculerMode {
                    sectionMode
                }
                sectionType
                if estCardio {
                    sectionStructureEffort
                }
                if mode == .manuel {
                    SectionDateHeure(date: $dateDebut)
                    sectionDuree
                    sectionIntensite
                    sectionGlucides
                    sectionNote
                } else {
                    sectionDemarrer
                }
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(estEdition ? "Modifier" : "Nouvelle activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                if mode == .manuel {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Enregistrer") { confirmer() }
                            .disabled(!peutValider)
                            .fontWeight(.semibold)
                    }
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
        .sheet(isPresented: $afficherRechercheAliment) {
            SheetRechercheAlimentSimple(titre: "Glucides pré-sport") { aliment in
                alimentsPreSport.append(aliment)
            }
        }
    }

    // MARK: - Section mode (chrono / manuel)
    //
    // Sélecteur segmenté en tête : « Chrono en direct » démarre une séance
    // chronométrée (heure de début + durée capturées automatiquement),
    // « Saisie manuelle » ouvre le formulaire rétrospectif complet.

    private var sectionMode: some View {
        Section {
            Picker("Mode", selection: $mode) {
                Text("Chrono en direct").tag(ModeCreation.direct)
                Text("Saisie manuelle").tag(ModeCreation.manuel)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .font(.body.weight(.medium))
            .padding(.vertical, 10)
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Section démarrer (mode chrono)
    //
    // Grand bouton d'action, désactivé tant qu'aucun sport n'est choisi — et,
    // pour un sport cardio, tant que la structure d'effort n'est pas choisie
    // non plus (`peutValider`). Empêche de démarrer une séance cardio sans
    // avoir déclaré continu/fractionné : cette info ne se rattrape pas après
    // coup de façon fiable.
    private var sectionDemarrer: some View {
        Section {
            Button {
                demarrer()
            } label: {
                Label(
                    typeSelectionne.map { "Démarrer : \($0.rawValue.lowercased())" } ?? "Démarrer la séance",
                    systemImage: "play.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(peutValider ? Color.accentColor : Color.secondary)
            .disabled(!peutValider)
            // Fond plein pleine largeur (teinte accent) sans capsule ni carte
            // flottante : c'est la row groupée elle-même qui porte la teinte.
            .listRowBackground(
                (peutValider ? Color.accentColor : Color.gray).opacity(0.15)
            )
        } footer: {
            Text("L'heure de début et la durée sont capturées automatiquement. Vous enregistrerez les détails à la fin.")
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

    // MARK: - Section structure d'effort
    //
    // Continu/fractionné — pertinent uniquement pour les sports cardio
    // (course, vélo, natation, marche, sport collectif) : la littérature
    // distingue leurs régimes glycémiques (voir doc Eraser S1). Masquée pour
    // musculation/yoga/autre plutôt que désactivée — pas de choix à faire là
    // où la distinction n'a pas de sens.
    private var estCardio: Bool {
        typeSelectionne?.categorie == .cardio
    }

    /// Un type de sport doit être choisi ; pour un sport cardio, la structure
    /// d'effort aussi (continu/fractionné) — pas de valeur par défaut
    /// implicite, l'app ne devine pas cette info.
    private var peutValider: Bool {
        typeSelectionne != nil && (!estCardio || structureEffort != nil)
    }

    private var sectionStructureEffort: some View {
        Section {
            VStack(spacing: 8) {
                ForEach(StructureEffort.allCases, id: \.self) { structure in
                    CarteRadioStructureEffort(
                        structure: structure,
                        selectionnee: structureEffort == structure
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            structureEffort = structureEffort == structure ? nil : structure
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Structure d'effort")
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

    // MARK: - Section glucides pré-sport
    //
    // Liste d'aliments (recherche, même moteur que la saisie repas) plutôt
    // qu'un simple champ grammes — quantité ET type comptent (cinétique du
    // glucide, cf. doc Eraser S1). Composant partagé avec le resucrage.
    private var sectionGlucides: some View {
        SectionAlimentsAjoutes(
            titreSection: "Glucides pré-sport",
            footer: "Enregistré comme un resucrage « préventif maintien » 30 minutes avant le début, pour que son effet soit analysé au même titre que ceux pris pendant la séance.",
            aliments: $alimentsPreSport,
            onAjouter: { afficherRechercheAliment = true }
        )
    }

    // MARK: - Section note
    private var sectionNote: some View {
        Section("Note") {
            TextField("Ajouter une note...", text: $note, axis: .vertical)
                .lineLimit(2...4)
        }
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
            // En création, les glucides pré-sport partent dans le hub comme
            // resucrages (voir `creerResucragesPreSport`). En édition on
            // préserve le champ tel quel : les activités enregistrées avant ce
            // changement portent encore leurs aliments ici.
            alimentsPreSport: estEdition ? alimentsPreSport : [],
            structureEffort: estCardio ? structureEffort : nil,
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
        )
        onValider(activite)
        creerResucragesPreSport()
        dismiss()
    }

    /// Un resucrage « préventif maintien » par aliment pré-sport, daté 30 min
    /// avant le début — délai usuel entre une collation et le départ, et
    /// cohérent avec la fenêtre de jugement de cette intention.
    ///
    /// Création seulement : en édition, les resucrages déjà créés sont des
    /// faits de hub autonomes, qui se modifient depuis la page Resucrage.
    private func creerResucragesPreSport() {
        guard !estEdition, !alimentsPreSport.isEmpty else { return }
        let instant = dateDebut.addingTimeInterval(-30 * 60)
        onCreerResucrages?([
            Resucrage(
                date: instant,
                intention: .preventifMaintien,
                aliments: alimentsPreSport
            )
        ])
    }

    private func demarrer() {
        guard let type = typeSelectionne else { return }
        onDemarrer?(type, estCardio ? structureEffort : nil)
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

#if DEBUG
#Preview("Création") {
    SheetNouvelleActivite(onValider: { _ in })
}

#Preview("Édition") {
    let act = ActiviteSportive(
        type: .course,
        dateDebut: Date(),
        dureeMinutes: 45,
        intensite: .moderee,
        alimentsPreSport: [.collationGenerique(glucidesGrammes: 15)],
        note: "Footing au parc"
    )
    return SheetNouvelleActivite(activiteExistante: act, onValider: { _ in })
}
#endif
