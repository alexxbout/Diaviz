//
//  SheetNouveauResucrage.swift
//  diaviz
//

import SwiftUI

/// Sheet de création d'un resucrage — intention obligatoire, aliments
/// (recherche, même moteur que glucides pré-sport), glycémie cible
/// optionnelle. Pas d'édition en V1 (créer/supprimer seulement) : un
/// resucrage se corrige en le supprimant et le re-créant, pas de flux
/// d'édition dédié pour l'instant.
struct SheetNouveauResucrage: View {

    let onValider: (Resucrage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var intention: IntentionResucrage?
    @State private var date = Date()
    @State private var aliments: [Aliment] = []
    @State private var glycemieCibleTexte = ""
    @State private var afficherRechercheAliment = false

    /// Intention obligatoire — pas de valeur par défaut implicite, seul
    /// l'utilisateur sait pourquoi (voir doc Eraser S1).
    private var peutValider: Bool { intention != nil }

    var body: some View {
        NavigationStack {
            Form {
                sectionIntention
                sectionCible
                SectionDateHeure(date: $date)
                SectionAlimentsAjoutes(
                    titreSection: "Aliments",
                    footer: "Aliments pris pour ce resucrage.",
                    aliments: $aliments,
                    onAjouter: { afficherRechercheAliment = true }
                )
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Resucrage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { confirmer() }
                        .disabled(!peutValider)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .sheet(isPresented: $afficherRechercheAliment) {
            SheetRechercheAlimentSimple(titre: "Resucrage") { aliment in
                aliments.append(aliment)
            }
        }
    }

    // MARK: - Section intention
    //
    // Obligatoire — bouton Enregistrer désactivé tant que rien n'est choisi,
    // même pattern que la structure d'effort sport.
    private var sectionIntention: some View {
        Section {
            VStack(spacing: 8) {
                ForEach(IntentionResucrage.allCases, id: \.self) { valeur in
                    CarteRadioIntention(
                        intention: valeur,
                        selectionnee: intention == valeur
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            intention = valeur
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Intention")
        }
    }

    // MARK: - Section glycémie cible
    private var sectionCible: some View {
        Section {
            HStack {
                TextField("Optionnel", text: $glycemieCibleTexte)
                    .keyboardType(.numberPad)
                Text("mg/dL")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Glycémie cible")
        } footer: {
            Text("À renseigner si vous visez une valeur précise plutôt qu'un resucrage standard.")
        }
    }

    // MARK: - Actions

    private var glycemieCibleDouble: Double? {
        let trim = glycemieCibleTexte.trimmingCharacters(in: .whitespaces)
        return trim.isEmpty ? nil : Double(trim)
    }

    private func confirmer() {
        guard let intention else { return }
        let resucrage = Resucrage(
            date: date,
            intention: intention,
            aliments: aliments,
            glycemieCible: glycemieCibleDouble
        )
        onValider(resucrage)
        dismiss()
    }
}

// MARK: - Aperçu

#Preview {
    SheetNouveauResucrage(onValider: { _ in })
}
