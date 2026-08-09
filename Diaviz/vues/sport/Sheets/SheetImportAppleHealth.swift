//
//  SheetImportAppleHealth.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

/// Sheet plein-écran présentant les workouts Apple Santé en attente
/// d'import dans diaviz.
///
/// Architecture en trois zones verticales :
/// 1. **Header** — icône cœur rouge + titre + nombre d'activités.
/// 2. **Liste de cartes** — `ScrollView` de `CarteWorkoutImport`
///    sélectionnables. Chaque carte expose un binding sur son
///    `EtatSelectionWorkout` (sélection + intensité).
/// 3. **Bouton flottant** — `safeAreaInset(edge: .bottom)` posé sur un
///    `.regularMaterial` pour le rendu Liquid Glass iOS 26. Le libellé
///    et l'état activé sont dérivés du nombre de cartes sélectionnées.
///
/// L'intensité de chaque carte est pré-remplie à partir de la FC moyenne
/// du workout via `intensiteDepuisFC(_:)` — l'utilisateur peut ajuster.
struct SheetImportAppleHealth: View {

    // MARK: - Paramètres

    /// Service injecté plutôt qu'accédé via le singleton — permet aux
    /// previews de présenter plusieurs états (vide / 1 / 3 activités)
    /// sans contaminer le state global.
    let service: HealthKitImportService

    /// Persiste l'`ActiviteSportive` construite à l'import dans le hub.
    /// Fourni par la vue appelante qui détient le `ActivitesSportService` —
    /// le service d'import ne connaît pas le `ModelContext`. `nil` dans les
    /// previews isolées (l'import ne fait alors que vider la file d'attente).
    let onImporter: ((ActiviteSportive) -> Void)?

    /// Le default `nil` + résolution dans le corps évite que l'expression
    /// `.shared` (isolée `@MainActor`) ne soit évaluée dans le contexte
    /// non-isolé d'un argument par défaut, ce qui déclencherait une erreur
    /// en Swift 6 strict.
    init(
        service: HealthKitImportService? = nil,
        onImporter: ((ActiviteSportive) -> Void)? = nil
    ) {
        self.service = service ?? .shared
        self.onImporter = onImporter
    }

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local
    //
    // Dictionnaire indexé par `id` de workout. L'init le dérive depuis
    // les workouts en attente du service. Tous les champs sont
    // initialisés à des défauts raisonnables (non sélectionnée,
    // glucides vides, intensité dérivée de la FC).

    @State private var etats: [UUID: EtatSelectionWorkout] = [:]

    // MARK: - Calculs dérivés

    private var workouts: [WorkoutHealthKitCandidat] {
        service.workoutsEnAttente
    }

    /// Nombre de cartes actuellement sélectionnées — alimente le label
    /// du bouton flottant et son état désactivé.
    private var nombreSelectionnees: Int {
        etats.values.filter(\.selectionnee).count
    }

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            contenuPrincipal
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { boutonAnnuler }
                .safeAreaInset(edge: .bottom) {
                    barreImporter
                }
        }
        .task { initialiserEtats() }
    }

    // MARK: - Contenu

    /// Conteneur défilable — l'en-tête fait partie du scroll pour pouvoir
    /// disparaître proprement quand la liste est longue, sans rester
    /// figé en haut comme un large title.
    private var contenuPrincipal: some View {
        ScrollView {
            VStack(spacing: 0) {
                enTete
                if workouts.isEmpty {
                    etatVide
                } else {
                    sousTitre
                    listeCartes
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - En-tête
    //
    // Icône SF Symbol `heart.text.square.fill` taille 64 en rouge —
    // pas d'icône officielle Apple Santé (Apple ne licencie pas son
    // logo aux apps tierces). Le rouge système suffit pour signaler
    // la provenance.

    private var enTete: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Apple Santé")
                .font(.title.bold())

            Text(libelleNombreActivites)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    /// Singulier/pluriel français — accord sur « activité » ET sur
    /// « détectée ».
    private var libelleNombreActivites: String {
        let n = workouts.count
        if n == 0 { return "Aucune activité détectée" }
        if n == 1 { return "1 activité détectée" }
        return "\(n) activités détectées"
    }

    private var sousTitre: some View {
        Text("Sélectionnez les activités à importer dans Diaviz.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
    }

    // MARK: - État vide

    private var etatVide: some View {
        ContentUnavailableView(
            "Aucune activité en attente",
            systemImage: "checkmark.circle",
            description: Text("Toutes les activités détectées par votre Apple Watch ont déjà été traitées.")
        )
        .padding(.top, 24)
    }

    // MARK: - Liste des cartes

    private var listeCartes: some View {
        LazyVStack(spacing: 12) {
            ForEach(workouts) { workout in
                if let etat = binding(pour: workout.id) {
                    CarteWorkoutImport(workout: workout, etat: etat)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    /// Construit un binding vers l'entrée du dictionnaire pour un id
    /// donné. Renvoie `nil` si l'entrée n'existe pas — protection
    /// contre une race fugitive entre `task` et le premier rendu.
    private func binding(pour id: UUID) -> Binding<EtatSelectionWorkout>? {
        guard etats[id] != nil else { return nil }
        return Binding(
            get: { etats[id] ?? .init(intensite: .moderee) },
            set: { etats[id] = $0 }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var boutonAnnuler: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Annuler", role: .cancel) { dismiss() }
        }
    }

    // MARK: - Barre flottante du bas
    //
    // Posée en `safeAreaInset` pour rester collée au bas du ScrollView
    // tout en respectant la home indicator. Background `.regularMaterial`
    // — sur iOS 26 ce matériau bénéficie automatiquement du rendu
    // Liquid Glass quand il flotte au-dessus de contenu défilant.

    private var barreImporter: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: importerToutes) {
                Text(libelleBoutonImporter)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(nombreSelectionnees == 0 || workouts.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial)
    }

    private var libelleBoutonImporter: String {
        switch nombreSelectionnees {
        case 0:  "Sélectionnez une activité"
        case 1:  "Importer (1 sélection)"
        default: "Importer (\(nombreSelectionnees) sélections)"
        }
    }

    // MARK: - Actions

    /// Initialise un état de sélection pour chaque workout en attente.
    /// L'intensité est dérivée de la FC moyenne du workout — bonne
    /// approximation par défaut, ajustable au tap.
    private func initialiserEtats() {
        var nouveau: [UUID: EtatSelectionWorkout] = [:]
        for w in workouts {
            // Conserve l'éventuel état déjà saisi si l'utilisateur a
            // remonté la sheet sans la fermer (édge-case mais pas cher
            // à gérer).
            if let existant = etats[w.id] {
                nouveau[w.id] = existant
            } else {
                nouveau[w.id] = EtatSelectionWorkout(
                    intensite: intensiteDepuisFC(w.fcMoyenne)
                )
            }
        }
        etats = nouveau
    }

    /// Applique l'import sur toutes les cartes sélectionnées, puis ferme
    /// la sheet. Les cartes non sélectionnées restent en attente — leurs
    /// badges resteront visibles à la prochaine ouverture.
    private func importerToutes() {
        for workout in workouts {
            guard let etat = etats[workout.id], etat.selectionnee else { continue }
            let activite = service.importer(
                workout,
                glucidesPreSport: nil,
                intensite: etat.intensite
            )
            onImporter?(activite)
        }
        dismiss()
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Aucune activité") {
    SheetImportAppleHealth(service: .mockVide())
}

#Preview("1 activité") {
    SheetImportAppleHealth(
        service: .mockAvecActivites([.mockCourse])
    )
}

#Preview("3 activités") {
    SheetImportAppleHealth(
        service: .mockAvecActivites([.mockCourse, .mockYoga, .mockMusculation])
    )
}
#endif
