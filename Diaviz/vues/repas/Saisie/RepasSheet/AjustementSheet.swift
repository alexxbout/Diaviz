//
//  AjustementSheet.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

// MARK: - Modèle

/// Raisons possibles pour ajuster intentionnellement la dose d'insuline
/// par rapport à ce que le ratio recommanderait. Distinct d'une correction
/// d'hyperglycémie (gérée séparément dans `InsulineSection`).
enum RaisonAjustement: String, CaseIterable, Identifiable, Equatable, Codable {
    case sportRecent
    case glycemieBasse
    case repasGras
    case incertitudeGlucides
    case insulineActive
    case autre

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .sportRecent:         return "Sport récent"
        case .glycemieBasse:       return "Glycémie basse avant repas"
        case .repasGras:           return "Repas riche en graisse"
        case .incertitudeGlucides: return "Incertitude sur les glucides"
        case .insulineActive:      return "Insuline encore active"
        case .autre:                return "Autre"
        }
    }

    var icone: String {
        switch self {
        case .sportRecent:         return "figure.run"
        case .glycemieBasse:       return "chart.line.downtrend.xyaxis"
        case .repasGras:           return "drop.triangle"
        case .incertitudeGlucides: return "questionmark.circle"
        case .insulineActive:      return "syringe"
        case .autre:                return "ellipsis.circle"
        }
    }
}

/// Couple raison + valeur. La valeur est signée :
/// - négative pour réduire (sport, hypo, IOB, ...)
/// - positive pour augmenter (repas gras, etc.)
///
/// `Identifiable` pour permettre une liste éditable de plusieurs ajustements.
/// L'`id` est préservé via copie de struct lors d'une édition.
struct Ajustement: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var raison: RaisonAjustement
    var valeur: Double
    /// Type de sport détecté au moment de la saisie (ex. « Course à pied »),
    /// rempli automatiquement pour un ajustement `.sportRecent` quand une
    /// activité récente est présente dans le hub (`InsightsService.sportRecent`).
    /// `nil` pour toute autre raison, ou si aucun sport n'a été détecté.
    var typeSportDetecte: String? = nil
}

// MARK: - Sheet

/// Sheet de saisie d'un ajustement intentionnel : choix de la raison + valeur.
///
/// Mode unifié pour ajout et édition :
/// - `ajustementInitial` est l'état de départ. En ajout, c'est un nouveau
///   `Ajustement` avec valeurs par défaut. En édition, c'est l'existant
///   passé par l'appelant (son `id` est préservé).
/// - `onValider` est appelé avec le résultat à la confirmation.
/// - `onSupprimer` est non-nil uniquement en mode édition ; affiche la
///   section de suppression.
struct AjustementSheet: View {

    let ajustementInitial: Ajustement
    let onValider: (Ajustement) -> Void
    let onSupprimer: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var raisonChoisie: RaisonAjustement
    @State private var valeur: Double

    init(
        ajustementInitial: Ajustement,
        onValider: @escaping (Ajustement) -> Void,
        onSupprimer: (() -> Void)? = nil
    ) {
        self.ajustementInitial = ajustementInitial
        self.onValider = onValider
        self.onSupprimer = onSupprimer
        self._raisonChoisie = State(initialValue: ajustementInitial.raison)
        self._valeur = State(initialValue: ajustementInitial.valeur)
    }

    private var enEdition: Bool { onSupprimer != nil }

    var body: some View {
        NavigationStack {
            Form {
                sectionRaison
                sectionValeur
                if enEdition, let onSupprimer {
                    sectionSuppression(onSupprimer: onSupprimer)
                }
            }
            .navigationTitle(enEdition ? "Modifier l'ajustement" : "Nouvel ajustement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(enEdition ? "Enregistrer" : "Ajouter") {
                        var maj = ajustementInitial
                        maj.raison = raisonChoisie
                        maj.valeur = valeur
                        // Le type de sport détecté n'a de sens que pour la
                        // raison « sport récent » — un changement de raison
                        // via le picker ne doit pas le laisser traîner.
                        maj.typeSportDetecte = raisonChoisie == .sportRecent
                            ? ajustementInitial.typeSportDetecte : nil
                        onValider(maj)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(valeur == 0)
                }
            }
        }
        // Plein écran : la sheet d'ajustement contient une liste de raisons,
        // une row de saisie et un bouton suppression. Tout doit être visible
        // sans avoir à scroller.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Pas de Liquid Glass sur les sheets internes — fond plat aligné
        // sur le style grouped form pour rester lisible.
        .presentationBackground(Color(.systemGroupedBackground))
    }

    // MARK: - Sections

    private var sectionRaison: some View {
        Section("Raison") {
            ForEach(RaisonAjustement.allCases) { raison in
                Button {
                    raisonChoisie = raison
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: raison.icone)
                            .font(.title3)
                            .frame(width: 24)
                        Text(raison.libelle)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        if raisonChoisie == raison {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .font(.body.bold())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// `StepperDose` partagé — plage signée (un ajustement retranche ou ajoute
    /// de la dose) et tap au centre pour la saisie directe au clavier.
    private var sectionValeur: some View {
        Section("Valeur") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ajustement")
                    .font(.body)

                StepperDose(
                    valeur: $valeur,
                    plage: -5...5,
                    titreSaisie: "Valeur de l'ajustement",
                    afficheSigne: true,
                    couleur: { $0 < 0 ? .orange : ($0 > 0 ? .red : .secondary) }
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func sectionSuppression(onSupprimer: @escaping () -> Void) -> some View {
        Section {
            Button("Supprimer cet ajustement", role: .destructive) {
                onSupprimer()
                dismiss()
            }
        }
    }

}

#if DEBUG
#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AjustementSheet(
                ajustementInitial: Ajustement(raison: .sportRecent, valeur: -0.5),
                onValider: { _ in }
            )
        }
}
#endif
