//
//  AjouterRepasVue.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

// Catégories de filtrage disponibles dans la barre de segmentation
enum FiltreAliment: String, CaseIterable {
    case bruts = "Bruts"
    case produits = "Produits"
    case mesAliments = "Mes aliments"
}

struct AjouterRepasVue: View {
    @State private var recherche: String = ""
    @State private var resultats: [AlimentCiqual] = []
    @State private var filtre: FiltreAliment = .bruts
    @State private var scannerCodeBarres = false

    var body: some View {
        VStack(spacing: 0) {
            // Barre de recherche custom + bouton scanner côte à côte
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 17, weight: .regular))

                    TextField("Rechercher un aliment...", text: $recherche)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .submitLabel(.search)

                    // Bouton effacer visible seulement quand du texte est saisi
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

            // Filtre par catégorie d'aliment (non encore branché sur les résultats)
            Picker("Filtre", selection: $filtre) {
                ForEach(FiltreAliment.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .controlSize(ControlSize.large)
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 12)

            if recherche.isEmpty {
                // Affiche les 10 derniers aliments utilisés, ou un état vide
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
                    }
                }
            } else {
                // Résultats filtrés en temps réel via l'algorithme à 5 niveaux de pertinence
                List(resultats) { aliment in
                    LigneAliment(aliment: aliment)
                }
                .onChange(of: recherche) { _, nouveau in
                    resultats = CiqualService.shared.rechercher(nouveau)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // Visible uniquement quand des récents existent et que la recherche est vide
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
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Nouveau repas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scannerCodeBarres) {
            Text("Scanner un code-barres")
                .presentationDetents([.medium])
        }
    }
}

#Preview {
    NavigationStack {
        AjouterRepasVue()
    }
}
