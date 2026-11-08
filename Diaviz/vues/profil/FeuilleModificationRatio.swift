//
//  FeuilleModificationRatio.swift
//  diaviz
//

import SwiftUI

/// Feuille ouverte au toucher d'une ligne de ratio. La valeur n'est appliquée
/// qu'à « Enregistrer » : passer de 10 à 12 ne fait qu'un seul changement.
/// Un ratio verrouillé n'offre aucun réglage, sauf passage volontaire par
/// « Modifier quand même » (ratio changé par le médecin, par exemple).
struct FeuilleModificationRatio: View {

    let libelle: String
    let valeurActuelle: Double?
    let dateChangement: Date?
    let nombreRepas: Int
    let etat: CalculVerrouRatio.Etat
    let enregistrer: (Double) -> Void

    @Environment(\.dismiss) private var fermer
    @State private var brouillon: Double
    @State private var deverrouille = false
    @State private var confirmation = false

    init(
        libelle: String,
        valeurActuelle: Double?,
        dateChangement: Date?,
        nombreRepas: Int,
        etat: CalculVerrouRatio.Etat,
        enregistrer: @escaping (Double) -> Void
    ) {
        self.libelle = libelle
        self.valeurActuelle = valeurActuelle
        self.dateChangement = dateChangement
        self.nombreRepas = nombreRepas
        self.etat = etat
        self.enregistrer = enregistrer
        _brouillon = State(initialValue: valeurActuelle ?? 10)
    }

    private var phraseVerrou: String? {
        guard !deverrouille, case let .verrouille(restants, deblocage) = etat else { return nil }
        let repas = restants == CalculVerrouRatio.repasRequis
            ? "\(restants) repas"
            : "\(restants) repas de plus"
        return "Modifiable après \(repas), ou le \(FormatRatio.date(deblocage))"
    }

    private var peutEnregistrer: Bool {
        phraseVerrou == nil && brouillon != valeurActuelle
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Text(FormatRatio.valeur(brouillon))
                            .font(.largeTitle.bold())
                            .monospacedDigit()
                            .contentTransition(.numericText(value: brouillon))
                            .animation(.snappy, value: brouillon)
                        if let valeurActuelle, phraseVerrou == nil {
                            Text("Actuel : \(FormatRatio.valeur(valeurActuelle))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if phraseVerrou == nil {
                            Stepper("Ratio", value: $brouillon, in: 5...30, step: 1)
                                .labelsHidden()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                if let phraseVerrou {
                    Section { Text(phraseVerrou) }
                }

                if valeurActuelle != nil {
                    Section {
                        LabeledContent(
                            "Dernier changement",
                            value: dateChangement.map(FormatRatio.date) ?? "Jamais"
                        )
                        LabeledContent("Repas avec ce ratio", value: "\(nombreRepas)")
                    } footer: {
                        if phraseVerrou == nil {
                            Text("Après enregistrement, l'analyse de ce moment repart de zéro.")
                        }
                    }
                }

                if phraseVerrou != nil {
                    Section {
                        Button("Modifier quand même…") { confirmation = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(libelle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { barre }
            .confirmationDialog(
                "Modifier ce ratio maintenant ?",
                isPresented: $confirmation,
                titleVisibility: .visible
            ) {
                Button("Modifier quand même") { deverrouille = true }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("L'analyse de ce moment repartira de zéro, avec peu de recul sur le réglage actuel.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ToolbarContentBuilder
    private var barre: some ToolbarContent {
        if phraseVerrou == nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { fermer() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    enregistrer(brouillon)
                    fermer()
                }
                .disabled(!peutEnregistrer)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { fermer() }
            }
        }
    }
}

/// Textes partagés entre la liste des ratios et sa feuille.
enum FormatRatio {
    static func valeur(_ ratio: Double) -> String {
        "1u / \(Int(ratio))g"
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
