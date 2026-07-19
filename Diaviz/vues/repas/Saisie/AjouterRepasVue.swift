//
//  AjouterRepasVue.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI
import SwiftData

/// Catégories de filtrage disponibles dans la barre de segmentation.
/// `.bruts` → recherche CIQUAL locale (à la frappe), `.produits` → recherche
/// Open Food Facts (déclenchement explicite), `.mesAliments` → pas encore branché.
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

    /// État de la recherche Open Food Facts (onglet « Produits ») :
    /// résultats, chargement, erreur et cache session.
    @State private var rechercheProduits = RechercheProduitsService()

    /// Aliments du repas en cours. Tant que vide, la bulle ne s'affiche pas.
    @State private var alimentsRepas: [EntreeAliment] = []

    /// Aliment sélectionné depuis la liste de recherche — déclenche
    /// `DetailAlimentSheet` pour configurer la quantité, la dose, etc.
    @State private var alimentSelectionne: ResultatRechercheAliment? = nil

    /// Présentation de `RepasSheet` (déclenchée par tap/drag sur la bulle).
    @State private var repasSheetPresentee: Bool = false

    /// Présentation de la sheet listant les aliments CIQUAL masqués.
    @State private var alimentsCachesPresentee: Bool = false

    /// Trigger du retour haptique au masquage d'un aliment (swipe).
    @State private var triggerMasquage: Int = 0

    /// Focus de la barre de recherche — réactivé quand l'utilisateur tape
    /// "Ajouter un aliment" depuis la `RepasSheet`.
    @FocusState private var rechercheActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            barreRecherche
            filtreSegmente
            contenuPrincipal
                .sensoryFeedback(.success, trigger: triggerMasquage)
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
            // Pas de `marquerUtilise` ici : l'aliment n'est encore
            // qu'ajouté au repas EN COURS, pas persisté. Le flag "récemment
            // ajouté" n'a de sens qu'après validation réelle du repas
            // (`validerRepas`), sinon un aliment configuré puis abandonné
            // (repas jamais validé) resterait marqué à tort.
            DetailAlimentSheet(aliment: aliment) { entree in
                alimentsRepas.append(entree)
            }
        }
        // RepasSheet — plein écran (`.large` only). L'utilisateur peut
        // dismiss par swipe-down et revenir à la bulle en overlay.
        .sheet(isPresented: $repasSheetPresentee) {
            RepasSheet(
                aliments: $alimentsRepas,
                onAjouterUnAliment: tapperAjouterAliment,
                onValiderRepas: { dose, site, heure, doseGlobale in
                    validerRepas(
                        doseInjectee: dose,
                        site: site,
                        heure: heure,
                        doseGlobale: doseGlobale
                    )
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $alimentsCachesPresentee) {
            AlimentsCachesSheet()
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
    /// l'état de saisie. L'horodatage du repas est l'**heure choisie dans la
    /// sheet** (préremplie à l'instant courant, réglable pour une saisie
    /// rétroactive) — c'est le fait brut horodaté attendu par le hub. La
    /// réponse glycémique (`etatAnalyse`) reste une dérivation non calculée ici.
    private func validerRepas(
        doseInjectee: Double,
        site: SiteInjection,
        heure: Date,
        doseGlobale: Double?
    ) {
        repasService.enregistrerDepuisSaisie(
            entrees: alimentsRepas,
            heure: heure,
            doseInjectee: doseInjectee,
            site: site,
            doseGlobale: doseGlobale
        )
        // Marqué "récemment ajouté" seulement maintenant, à la persistance
        // réelle du repas — pas à la simple composition en cours.
        for entree in alimentsRepas {
            AlimentsRecentsService.shared.marquerUtilise(entree.aliment)
        }
        alimentsRepas.removeAll()
        recherche = ""
        rechercheProduits.reinitialiserAffichage()
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
                    // Recherche OFF déclenchée explicitement (bouton
                    // « rechercher » du clavier) — jamais à la frappe,
                    // l'API externe est sous quota (10 req/min).
                    .onSubmit {
                        if filtre == .produits {
                            rechercheProduits.rechercher(recherche)
                        }
                    }

                if !recherche.isEmpty {
                    Button {
                        recherche = ""
                        // Texte effacé → l'affichage OFF repart de zéro
                        // (le cache session, lui, est conservé).
                        rechercheProduits.reinitialiserAffichage()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 17))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // `secondarySystemGroupedBackground` plutôt que `systemBackground` :
            // en mode sombre les deux valent noir sur ce fond groupé
            // (`systemGroupedBackground`), la capsule devenait invisible.
            .background(Color(.secondarySystemGroupedBackground))
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
        .sensoryFeedback(.selection, trigger: filtre)
        .padding(.horizontal)
        .padding(.bottom, 12)
        // Bascule vers « Produits » avec un texte déjà saisi → recherche OFF.
        // Le cache session du service évite tout appel réseau si le terme n'a
        // pas changé entre deux bascules (Produits → Bruts → Produits).
        .onChange(of: filtre) { _, nouveau in
            if nouveau == .produits && !recherche.isEmpty {
                rechercheProduits.rechercher(recherche)
            }
        }
    }

    /// Contenu principal : résultats de recherche, aliments récents,
    /// ou état vide selon le contexte et l'onglet.
    @ViewBuilder
    private var contenuPrincipal: some View {
        if recherche.isEmpty {
            vueRecents
        } else if filtre == .produits {
            vueResultatsProduits
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
                ligneAvecMasquage(aliment) { alimentSelectionne = aliment }
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

    /// Liste des résultats de recherche CIQUAL, filtrés en temps réel
    /// (recherche locale — pas de contrainte de quota).
    private var vueResultatsRecherche: some View {
        List(resultats) { aliment in
            ligneAvecMasquage(.ciqual(aliment)) {
                alimentSelectionne = .ciqual(aliment)
            } onMasque: {
                resultats.removeAll { $0.id == aliment.id }
            }
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

    /// Résultats de l'onglet « Produits » (Open Food Facts) : chargement,
    /// erreur, invite à lancer la recherche, ou liste de produits.
    @ViewBuilder
    private var vueResultatsProduits: some View {
        if rechercheProduits.enChargement {
            ProgressView("Recherche des produits…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let erreur = rechercheProduits.erreur {
            ContentUnavailableView(
                "Recherche impossible",
                systemImage: "wifi.exclamationmark",
                description: Text(erreur.messageUtilisateur)
            )
        } else if rechercheProduits.termeAffiche.isEmpty {
            ContentUnavailableView(
                "Rechercher un produit",
                systemImage: "magnifyingglass",
                description: Text("Appuie sur « rechercher » sur le clavier pour interroger Open Food Facts")
            )
        } else if rechercheProduits.resultats.isEmpty {
            ContentUnavailableView.search(text: rechercheProduits.termeAffiche)
        } else {
            List {
                ForEach(rechercheProduits.resultats) { produit in
                    LigneResultatRecherche(aliment: .off(produit))
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                alimentSelectionne = .off(produit)
                            }
                        )
                }
                // Pagination : une page de plus à chaque tap (10 produits).
                if rechercheProduits.peutChargerPlus {
                    Button {
                        rechercheProduits.chargerPlus()
                    } label: {
                        HStack {
                            Spacer()
                            if rechercheProduits.chargementPagePlus {
                                ProgressView()
                            } else {
                                Text("Afficher plus de produits")
                                    .foregroundStyle(.tint)
                            }
                            Spacer()
                        }
                    }
                    .disabled(rechercheProduits.chargementPagePlus)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .safeAreaPadding(.bottom, alimentsRepas.isEmpty ? 0 : 100)
            .transaction(value: alimentsRepas.isEmpty) { transaction in
                transaction.animation = nil
            }
        }
    }

    /// Ligne de résultat avec, pour les aliments **CIQUAL uniquement**, un
    /// swipe pour masquer l'aliment des suggestions (recherche + récents).
    /// Les produits Open Food Facts n'ont pas ce geste — l'utilisateur les a
    /// déjà choisis explicitement via une recherche, pas de bruit à filtrer.
    @ViewBuilder
    private func ligneAvecMasquage(
        _ aliment: ResultatRechercheAliment,
        onTap: @escaping () -> Void,
        onMasque: (() -> Void)? = nil
    ) -> some View {
        let ligne = LigneResultatRecherche(aliment: aliment)
            .simultaneousGesture(TapGesture().onEnded(onTap))

        if case .ciqual(let a) = aliment {
            ligne.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    AlimentsCachesService.shared.cacher(a.id)
                    triggerMasquage += 1
                    onMasque?()
                } label: {
                    Label("Masquer", systemImage: "eye.slash")
                }
            }
        } else {
            ligne
        }
    }

    /// Menu toolbar : toujours accessible (accès permanent aux aliments
    /// masqués), avec des entrées additionnelles selon le contexte.
    @ToolbarContentBuilder
    private var menuToolbar: some ToolbarContent {
        let aUnRepas = !alimentsRepas.isEmpty
        let peutEffacerRecents = recherche.isEmpty && !AlimentsRecentsService.shared.clesRecentes.isEmpty

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
                Button {
                    alimentsCachesPresentee = true
                } label: {
                    Label("Aliments masqués", systemImage: "eye.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
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
