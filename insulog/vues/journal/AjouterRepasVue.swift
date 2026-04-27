//
//  AjouterRepasVue.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

/// Catégories de filtrage disponibles dans la barre de segmentation.
/// Pour le moment, seul `.bruts` est branché sur la recherche CIQUAL.
enum FiltreAliment: String, CaseIterable {
    case bruts = "Bruts"
    case produits = "Produits"
    case mesAliments = "Mes aliments"
}

/// Vue principale de composition d'un repas.
/// Permet de rechercher des aliments dans CIQUAL et de les ajouter
/// progressivement à un repas en cours, résumé dans une bulle persistante.
struct AjouterRepasVue: View {
    @State private var recherche: String = ""
    @State private var resultats: [AlimentCiqual] = []
    @State private var filtre: FiltreAliment = .bruts
    @State private var scannerCodeBarres = false

    /// Aliments ajoutés au repas en cours.
    /// Tant qu'il est vide, la bulle reste cachée.
    @State private var alimentsRepas: [AlimentCiqual] = []

    var body: some View {
        VStack(spacing: 0) {
            barreRecherche
            filtreSegmente
            contenuPrincipal
        }
        .background(Color(.systemGroupedBackground), ignoresSafeAreaEdges: .all)
        .overlay(alignment: .bottom) {
            // La bulle est superposée à la liste plutôt que d'utiliser
            // safeAreaInset, qui ajoute un fond système indésirable.
            if !alimentsRepas.isEmpty {
                BulleRepasEnCours(aliments: $alimentsRepas)
                    .transition(.opacity.combined(with: .offset(y: 80)))
            }
        }
        // Anime UNIQUEMENT la transition d'apparition/disparition de la bulle.
        // Le changement d'état booléen `isEmpty` pilote l'animation,
        // pas chaque ajout d'aliment individuel.
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: alimentsRepas.isEmpty)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { menuToolbar }
        .navigationTitle("Nouveau repas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scannerCodeBarres) {
            Text("Scanner un code-barres")
                .presentationDetents([.medium])
        }
    }

    /// Barre de recherche custom + bouton scanner code-barres côte à côte.
    /// On utilise une search bar custom plutôt que `.searchable()` pour
    /// pouvoir afficher le bouton scanner à droite de la barre.
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

                // Bouton clear visible seulement quand du texte est saisi.
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
                            alimentsRepas.append(aliment)
                        }
                    )
            }
            .safeAreaPadding(.bottom, alimentsRepas.isEmpty ? 0 : 90)
            // Désactive l'animation du `safeAreaPadding` quand
            // `alimentsRepas.isEmpty` change. Sans cette transaction,
            // le padding s'animerait progressivement et exposerait
            // brièvement le fond système gris du List, créant un
            // rectangle parasite visible pendant la transition de la bulle.
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
                        alimentsRepas.append(aliment)
                    }
                )
        }
        .safeAreaPadding(.bottom, alimentsRepas.isEmpty ? 0 : 90)
        // Même logique que vueRecents : on désactive l'animation
        // sur le padding pour éviter le flash de fond système.
        .transaction(value: alimentsRepas.isEmpty) { transaction in
            transaction.animation = nil
        }
        .onChange(of: recherche) { _, nouveau in
            resultats = CiqualService.shared.rechercher(nouveau)
        }
    }

    /// Menu toolbar visible uniquement quand des récents existent
    /// et que la recherche est vide.
    @ToolbarContentBuilder
    private var menuToolbar: some ToolbarContent {
        if recherche.isEmpty && !AlimentsRecentsService.shared.idsRecents.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Effacer les suggestions", role: .destructive) {
                        AlimentsRecentsService.shared.effacer()
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
}
