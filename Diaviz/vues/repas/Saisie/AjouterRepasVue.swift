//
//  AjouterRepasVue.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI
import SwiftData

/// Catégories de filtrage disponibles dans la barre de segmentation.
/// Pour le moment, seul `.bruts` est branché sur la recherche CIQUAL.
enum FiltreAliment: String, CaseIterable {
    case bruts = "Bruts"
    case produits = "Produits"
    case mesAliments = "Mes aliments"
}

/// Vue principale de composition d'un repas.
///
/// Permet de rechercher des aliments dans CIQUAL et de les ajouter
/// progressivement à un repas en cours.
///
/// ## Présentation du repas
/// - Tant qu'aucun aliment n'est ajouté, rien n'est affiché en plus de la
///   liste de recherche.
/// - Dès qu'un aliment est ajouté, `BulleRepasEnCours` apparaît en
///   `.overlay(alignment: .bottom)` — capsule glass flottante avec le résumé
///   du repas (compteur d'aliments, total glucides).
/// - Tap ou drag-up sur la bulle → présente `RepasSheet` plein écran (`.large`)
///   avec toutes les sections (insuline, alertes, détails d'injection).
struct AjouterRepasVue: View {

    /// Service hub des repas, **partagé** via l'environnement (même instance que
    /// le journal) → un repas validé ici apparaît immédiatement dans la liste.
    /// La validation construit un `Repas` (mapping `EntreeAliment -> Aliment`)
    /// et l'enregistre via ce service.
    @Environment(RepasService.self) private var repasService

    @State private var recherche: String = ""
    @State private var resultats: [AlimentCiqual] = []
    @State private var filtre: FiltreAliment = .bruts
    @State private var scannerCodeBarres = false

    /// Aliments du repas en cours. Tant que vide, la bulle ne s'affiche pas.
    @State private var alimentsRepas: [EntreeAliment] = []

    /// Aliment sélectionné depuis la liste de recherche — déclenche
    /// `DetailAlimentSheet` pour configurer la quantité, la dose, etc.
    @State private var alimentSelectionne: AlimentCiqual? = nil

    /// Présentation de `RepasSheet` (déclenchée par tap/drag sur la bulle).
    @State private var repasSheetPresentee: Bool = false

    /// Focus de la barre de recherche — réactivé quand l'utilisateur tape
    /// "Ajouter un aliment" depuis la `RepasSheet`.
    @FocusState private var rechercheActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            barreRecherche
            filtreSegmente
            contenuPrincipal
        }
        .background(Color(.systemGroupedBackground), ignoresSafeAreaEdges: .all)
        // Bulle en overlay : composant SwiftUI normal (pas dans une sheet),
        // d'où le hit-testing fiable et le centrage propre.
        .overlay(alignment: .bottom) {
            if !alimentsRepas.isEmpty {
                BulleRepasEnCours(aliments: $alimentsRepas) {
                    repasSheetPresentee = true
                }
                .transition(.opacity.combined(with: .offset(y: 80)))
            }
        }
        // Anime UNIQUEMENT la transition d'apparition/disparition de la bulle
        // (le passage `aliments vide` ↔ `aliments non vide`), pas chaque
        // ajout d'aliment individuel.
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: alimentsRepas.isEmpty)
        .toolbar { menuToolbar }
        .navigationTitle("Nouveau repas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scannerCodeBarres) {
            Text("Scanner un code-barres")
                .presentationDetents([.medium])
        }
        // Sheet de détail d'un aliment — déclenchée à chaque sélection
        // depuis la barre de recherche. Plus besoin de filtre conditionnel
        // (la sheet `RepasSheet` est plein écran et bloque l'interaction
        // avec la barre de recherche → pas de conflit possible).
        .sheet(item: $alimentSelectionne) { aliment in
            DetailAlimentSheet(aliment: aliment) { entree in
                alimentsRepas.append(entree)
                AlimentsRecentsService.shared.marquerUtilise(aliment)
            }
        }
        // RepasSheet — plein écran (`.large` only). L'utilisateur peut
        // dismiss par swipe-down et revenir à la bulle en overlay.
        .sheet(isPresented: $repasSheetPresentee) {
            RepasSheet(
                aliments: $alimentsRepas,
                onAjouterUnAliment: tapperAjouterAliment,
                onValiderRepas: validerRepas
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Actions

    /// Tap sur "Ajouter un aliment" depuis la `RepasSheet` :
    /// ferme la sheet et focus la barre de recherche.
    private func tapperAjouterAliment() {
        repasSheetPresentee = false
        rechercheActive = true
    }

    /// Validation finale du repas : persiste le repas dans le hub puis reset
    /// l'état de saisie. L'horodatage du repas est l'instant de validation
    /// (`Date()`) — c'est le fait brut horodaté attendu par le hub. La réponse
    /// glycémique (`etatAnalyse`) reste une dérivation non calculée ici.
    private func validerRepas() {
        repasService.enregistrerDepuisSaisie(entrees: alimentsRepas)
        alimentsRepas.removeAll()
        recherche = ""
        repasSheetPresentee = false
    }

    // MARK: - Barre de recherche

    /// Barre de recherche custom + bouton scanner code-barres côte à côte.
    private var barreRecherche: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 17, weight: .regular))

                TextField("Rechercher un aliment...", text: $recherche)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .submitLabel(.search)
                    .focused($rechercheActive)

                if !recherche.isEmpty {
                    Button {
                        recherche = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 17))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(Capsule())

            Button {
                scannerCodeBarres = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Filtre par catégorie d'aliment (non encore branché sur les résultats).
    private var filtreSegmente: some View {
        Picker("Filtre", selection: $filtre) {
            ForEach(FiltreAliment.allCases, id: \.self) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .controlSize(.large)
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    /// Contenu principal : résultats de recherche, aliments récents,
    /// ou état vide selon le contexte.
    @ViewBuilder
    private var contenuPrincipal: some View {
        if recherche.isEmpty {
            vueRecents
        } else {
            vueResultatsRecherche
        }
    }

    /// Affiche les 10 derniers aliments utilisés, ou un état vide informatif.
    @ViewBuilder
    private var vueRecents: some View {
        let recents = AlimentsRecentsService.shared.alimentsRecents.prefix(10)

        if recents.isEmpty {
            ContentUnavailableView(
                "Aucun aliment récent",
                systemImage: "clock",
                description: Text("Vos aliments récents apparaîtront ici")
            )
        } else {
            List(Array(recents)) { aliment in
                LigneAliment(aliment: aliment)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            alimentSelectionne = aliment
                        }
                    )
            }
            .scrollDismissesKeyboard(.immediately)
            // Padding en bas pour ne pas que la bulle cache le dernier
            // aliment de la liste. 100pt = ~80pt de bulle + 20pt de marge.
            .safeAreaPadding(.bottom, alimentsRepas.isEmpty ? 0 : 100)
            // Désactive l'animation du padding pour éviter un flash de fond
            // système gris pendant la transition d'apparition de la bulle.
            .transaction(value: alimentsRepas.isEmpty) { transaction in
                transaction.animation = nil
            }
        }
    }

    /// Liste des résultats de recherche filtrés en temps réel.
    private var vueResultatsRecherche: some View {
        List(resultats) { aliment in
            LigneAliment(aliment: aliment)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        alimentSelectionne = aliment
                    }
                )
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaPadding(.bottom, alimentsRepas.isEmpty ? 0 : 100)
        .transaction(value: alimentsRepas.isEmpty) { transaction in
            transaction.animation = nil
        }
        .onChange(of: recherche) { _, nouveau in
            resultats = CiqualService.shared.rechercher(nouveau)
        }
    }

    /// Menu toolbar : visible quand au moins une action est applicable —
    /// repas en cours à supprimer, ou suggestions à effacer.
    @ToolbarContentBuilder
    private var menuToolbar: some ToolbarContent {
        let aUnRepas = !alimentsRepas.isEmpty
        let peutEffacerRecents = recherche.isEmpty && !AlimentsRecentsService.shared.idsRecents.isEmpty

        if aUnRepas || peutEffacerRecents {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if aUnRepas {
                        Button("Supprimer le repas en cours", role: .destructive) {
                            alimentsRepas.removeAll()
                        }
                    }
                    if peutEffacerRecents {
                        Button("Effacer les suggestions", role: .destructive) {
                            AlimentsRecentsService.shared.effacer()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AjouterRepasVue()
    }
    .environment(RepasService.apercu())
}
