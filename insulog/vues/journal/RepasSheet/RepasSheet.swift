//
//  RepasSheet.swift
//  insulog
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Sheet "Repas en cours" présentée plein écran (`.large`) au-dessus de
/// `AjouterRepasVue` quand l'utilisateur tape ou drag-up sur la bulle
/// (`BulleRepasEnCours` rendue en overlay sur le parent).
///
/// La sheet est purement le mode complet : en-tête, liste d'aliments,
/// section insuline, alertes, détails d'injection, et bouton de validation.
/// Elle peut empiler des sheets enfants (`DetailAlimentSheet` pour l'édition
/// d'un aliment, `AjustementSheet` pour les ajustements intentionnels).
struct RepasSheet: View {

    // MARK: - Bindings

    @Binding var aliments: [EntreeAliment]

    // MARK: - Closures

    /// "Ajouter un aliment" depuis la sheet : remonte au parent qui ferme
    /// la sheet et active la barre de recherche.
    let onAjouterUnAliment: () -> Void

    /// Validation finale du repas. Le parent reset l'état.
    let onValiderRepas: () -> Void

    // MARK: - État interne

    @State private var ajustements: [Ajustement] = []
    @State private var correctionHyper: Double = 0
    @State private var heureInjection: Date = .now
    @State private var siteInjection: SiteInjection = .parDefaut

    /// Entrée actuellement en cours d'édition (déclenche la sheet enfant).
    @State private var entreeEnEdition: EntreeAliment? = nil

    /// Routage unifié pour la sheet d'ajustement (ajout ou édition).
    @State private var sheetAjustement: SheetAjustement? = nil

    private var insightsService: InsightsService { .shared }
    private let derniereZoneRapideMockee: ZoneInjection? = .ventre

    // MARK: - Calculs

    private var doseTotaleRepas: Double {
        aliments.reduce(0) { $0 + ($1.doseInsuline ?? 0) }
    }

    private var glucidesTotal: Double {
        aliments.reduce(0) { $0 + $1.glucides }
    }

    private var totalAjustements: Double {
        ajustements.reduce(0) { $0 + $1.valeur }
    }

    private var totalInjecte: Double {
        max(0, doseTotaleRepas + totalAjustements + correctionHyper)
    }

    private var contexteInsights: ContexteInsights {
        insightsService.contexte(
            doseSaisie: totalInjecte,
            glucides: glucidesTotal
        )
    }

    // MARK: - Corps

    var body: some View {
        // Architecture : un seul `Form` contient toutes les sections, y
        // compris la section "Alertes". Les cartes ont une cornerRadius
        // qui matche le clip arrondi des sections de `Form.grouped` (~10pt)
        // pour que leurs bordures ne soient pas coupées aux coins.
        VStack(spacing: 0) {
            EnTeteSheet(
                nombreAliments: aliments.count,
                totalGlucides: glucidesTotal
            )

            Form {
                ListeAlimentsSection(
                    aliments: $aliments,
                    onEditer: { entreeEnEdition = $0 },
                    onAjouterUnAliment: onAjouterUnAliment
                )

                InsightsSection(contexte: contexteInsights)

                InsulineSection(
                    doseRepas: doseTotaleRepas,
                    ajustements: $ajustements,
                    correctionHyper: $correctionHyper,
                    totalInjecte: totalInjecte,
                    onAjouterAjustement: { sheetAjustement = .ajout },
                    onEditerAjustement: { sheetAjustement = .edition($0) }
                )

                DetailsSection(
                    heureInjection: $heureInjection,
                    siteInjection: $siteInjection,
                    derniereZoneRapide: derniereZoneRapideMockee
                )
            }
            .formStyle(.grouped)
        }
        .safeAreaInset(edge: .bottom) {
            BoutonValiderRepas(
                nombreAliments: aliments.count,
                onValider: onValiderRepas
            )
        }
        // Sheet enfant — édition d'une entrée existante (tap sur une row).
        .sheet(item: $entreeEnEdition) { entree in
            DetailAlimentSheet(
                aliment: entree.aliment,
                entreeExistante: entree
            ) { entreeMaj in
                remplacerEntree(entreeMaj)
            }
        }
        // Sheet d'ajustement intentionnel — ajout ou édition selon l'item.
        .sheet(item: $sheetAjustement) { item in
            switch item {
            case .ajout:
                AjustementSheet(
                    ajustementInitial: Ajustement(raison: .sportRecent, valeur: -0.5),
                    onValider: { nouveau in
                        ajustements.append(nouveau)
                    }
                )
            case .edition(let existante):
                AjustementSheet(
                    ajustementInitial: existante,
                    onValider: { maj in
                        if let idx = ajustements.firstIndex(where: { $0.id == maj.id }) {
                            ajustements[idx] = maj
                        }
                    },
                    onSupprimer: {
                        ajustements.removeAll { $0.id == existante.id }
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func remplacerEntree(_ entreeMaj: EntreeAliment) {
        if let idx = aliments.firstIndex(where: { $0.id == entreeMaj.id }) {
            aliments[idx] = entreeMaj
        }
    }
}

// MARK: - Routage de la sheet d'ajustement

/// Discrimine ajout vs édition pour la sheet d'ajustement, routé via un seul
/// `.sheet(item:)`.
private enum SheetAjustement: Identifiable {
    case ajout
    case edition(Ajustement)

    var id: String {
        switch self {
        case .ajout:                return "ajout"
        case .edition(let aj):      return aj.id.uuidString
        }
    }
}

// MARK: - Aperçu

private let _previewAlimentsRepas: [EntreeAliment] = [
    EntreeAliment(
        aliment: AlimentCiqual(id: 1, nom: "Pâtes complètes cuites", calories: 124, glucides: 25, sucres: 1, proteines: 5, lipides: 0.8, fibres: 3, emoji: "🍝"),
        quantiteGrammes: 200,
        quantiteApproximative: false,
        doseInsuline: 5.0,
        note: ""
    ),
    EntreeAliment(
        aliment: AlimentCiqual(id: 2, nom: "Poulet grillé", calories: 165, glucides: 0, sucres: 0, proteines: 31, lipides: 3.6, fibres: 0, emoji: "🍗"),
        quantiteGrammes: 150,
        quantiteApproximative: false,
        doseInsuline: 0.0,
        note: ""
    ),
    EntreeAliment(
        aliment: AlimentCiqual(id: 3, nom: "Yaourt nature", calories: 60, glucides: 5, sucres: 5, proteines: 4, lipides: 3, fibres: 0, emoji: "🥛"),
        quantiteGrammes: 125,
        quantiteApproximative: true,
        doseInsuline: 0.5,
        note: "Légère"
    ),
]

#Preview("Repas typique") {
    @Previewable @State var aliments = _previewAlimentsRepas
    RepasSheet(
        aliments: $aliments,
        onAjouterUnAliment: {},
        onValiderRepas: {}
    )
}

#Preview("Repas vide") {
    @Previewable @State var aliments: [EntreeAliment] = []
    RepasSheet(
        aliments: $aliments,
        onAjouterUnAliment: {},
        onValiderRepas: {}
    )
}
