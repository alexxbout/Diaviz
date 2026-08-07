//
//  SheetQuantiteAlimentSimple.swift
//  diaviz
//

import SwiftUI

/// Étape 2 de `SheetRechercheAlimentSimple` : quantité (grammes) pour
/// l'aliment choisi, glucides calculés en direct. Version allégée de
/// `DetailAlimentSheet` (pas d'insuline, pas de portions, pas de note) —
/// tout ce qu'il faut pour « quel aliment, quelle quantité, combien de
/// glucides », rien de plus.
struct SheetQuantiteAlimentSimple: View {

    let aliment: ResultatRechercheAliment
    let onValider: (Aliment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantiteGrammes: Double = 100
    @State private var afficherSaisie = false
    @State private var saisieTexte = ""

    private var glucides: Double { aliment.glucides * quantiteGrammes / 100 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    entete
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section("Quantité") {
                    HStack {
                        Text("Quantité")
                        Spacer()
                        Button {
                            saisieTexte = String(Int(quantiteGrammes))
                            afficherSaisie = true
                        } label: {
                            Text("\(Int(quantiteGrammes))g")
                                .font(.body.bold())
                                .contentTransition(.numericText())
                        }
                        .buttonStyle(.plain)
                    }
                    Slider(value: $quantiteGrammes, in: 5...max(300, quantiteGrammes), step: 5)
                        .animation(.spring(response: 0.3), value: quantiteGrammes)
                }

                Section("Glucides") {
                    HStack {
                        Text("Glucides")
                        Spacer()
                        Text("\(Int(glucides.rounded()))g")
                            .font(.body.bold())
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: glucides)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajouter") { confirmer() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Quantité en grammes", isPresented: $afficherSaisie) {
                TextField("ex : 150", text: $saisieTexte)
                    .keyboardType(.numberPad)
                Button("OK") { appliquerSaisie() }
                Button("Annuler", role: .cancel) { saisieTexte = "" }
            } message: {
                Text("Entrez la quantité en grammes (5–2000)")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private var entete: some View {
        VStack(spacing: 6) {
            Text(aliment.emoji ?? "🍽️")
                .font(.system(size: 60))
            Text(aliment.nom)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func appliquerSaisie() {
        let texte = saisieTexte.replacingOccurrences(of: ",", with: ".")
        if let valeur = Double(texte), valeur > 0 {
            withAnimation(.spring(response: 0.3)) {
                quantiteGrammes = max(5, min(2000, valeur))
            }
        }
        saisieTexte = ""
    }

    private func confirmer() {
        let idCiqual: Int? = {
            if case .ciqual(let a) = aliment { return a.id }
            return nil
        }()
        let nouvelAliment = Aliment(
            emoji: aliment.emoji ?? "🍽️",
            nom: aliment.nom,
            quantite: Int(quantiteGrammes),
            glucides: Int(glucides.rounded()),
            insuline: 0,
            idCiqualSource: idCiqual
        )
        onValider(nouvelAliment)
        dismiss()
    }
}

// MARK: - Aperçu

#Preview {
    let pomme = AlimentCiqual(id: 1, nom: "Pomme, pulpe et peau, crue", calories: 52, glucides: 12.6, sucres: 10.4, proteines: 0.3, lipides: 0.2, fibres: 2.4, emoji: "🍎")
    SheetQuantiteAlimentSimple(aliment: .ciqual(pomme), onValider: { _ in })
}
