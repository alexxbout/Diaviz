//
//  InsightsSection.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Section "Alertes" regroupant les cartes d'insights conditionnelles.
///
/// Une seule `Section` avec un `VStack` des cartes visibles. Cartes sans
/// bordure extérieure — l'identité visuelle vient du fond gradient et
/// de l'icône colorée.
///
/// Ordre d'affichage :
/// 1. SportDetecteCard (bleu) — fait du hub, peut changer le ratio en vigueur
/// 2. ValidationRatioCard (vert / orange / rouge selon état)
/// 3. IOBCard (indigo)
struct InsightsSection: View {

    let contexte: ContexteInsights
    /// Modification d'un repas enregistré : l'insuline active décrit l'état
    /// avant ce repas, et la carte le dit.
    var iobAvantRepas: Bool = false

    @State private var afficherInfo: Bool = false

    var body: some View {
        if aucunInsight {
            EmptyView()
        } else {
            Section {
                VStack(spacing: 10) {
                    // Le sport d'abord : c'est lui qui peut changer le ratio
                    // en vigueur, donc la cause avant la conséquence.
                    if let sport = contexte.sport {
                        SportDetecteCard(sport: sport)
                    }
                    if let validation = contexte.validation {
                        ValidationRatioCard(validation: validation, chargeSynthese: contexte.chargeSynthese)
                    }
                    if let iob = contexte.iob {
                        IOBCard(iob: iob, avantRepas: iobAvantRepas)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                headerAvecInfo
            }
            .alert("À propos des alertes", isPresented: $afficherInfo) {
                Button("OK") {}
            } message: {
                Text("Les alertes ci-dessous sont issues des données précédemment renseignées et ont pour objectif de mettre en évidence des points critiques qui pourraient impacter la dose d'insuline à faire pour ce repas.")
            }
        }
    }

    /// Header avec titre en casse normale + bouton info aligné à droite.
    /// `textCase(nil)` annule l'uppercase appliqué par défaut aux headers
    /// de Form en style grouped.
    private var headerAvecInfo: some View {
        HStack(spacing: 6) {
            Text("Alertes")
            Spacer()
            Button {
                afficherInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("À propos des alertes")
        }
        .textCase(nil)
    }

    private var aucunInsight: Bool {
        contexte.validation == nil && contexte.sport == nil && contexte.iob == nil
    }
}

// MARK: - Aperçu

// Données d'aperçu sous `#if DEBUG` : elles utilisent `.mockBaisse`, qui
// n'existe qu'en Debug. Laissées hors du bloc, elles cassaient le build Release.
#if DEBUG
private let _previewProfil = ProfilRatio(grammesParUnite: 10, libelle: "midi")

private let _previewContexteComplet = ContexteInsights(
    validation: ValidationRatio(doseSaisie: 0, doseSuggeree: 4.5, profil: _previewProfil),
    sport: SportDetecte(
        typeSport: "Yoga", icone: "figure.yoga", intensite: "Modérée", dureeMinutes: 60,
        debut: Date().addingTimeInterval(-2 * 3600), fin: Date().addingTimeInterval(-3600),
        minutesDepuisFin: 60, enCours: false, ratioAjuste: nil, minutesRestantesEffet: nil
    ),
    iob: IOB(
        unitesTotales: 1.8,
        injections: [
            InjectionActive(unitesInjectees: 2.0, heureInjection: Date().addingTimeInterval(-30 * 60), unitesRestantes: 1.2),
            InjectionActive(unitesInjectees: 1.0, heureInjection: Date().addingTimeInterval(-4 * 3600 - 30 * 60), unitesRestantes: 0.6),
        ]
    ),
    chargeSynthese: SyntheseChargeActive(etat: .disponible(indice: 0.5, niveau: .basse, depuisJours: 5), marcheIncluse: true)
)

private let _previewContexteCoherent = ContexteInsights(
    validation: ValidationRatio(doseSaisie: 4.5, doseSuggeree: 4.5, profil: _previewProfil),
    sport: nil,
    iob: nil,
    chargeSynthese: nil
)

#Preview("Trois alertes") {
    Form {
        InsightsSection(contexte: _previewContexteComplet)
    }
    .formStyle(.grouped)
}

#Preview("Validation cohérente seule") {
    Form {
        InsightsSection(contexte: _previewContexteCoherent)
    }
    .formStyle(.grouped)
}

#Preview("Aucune alerte (vue masquée)") {
    Form {
        InsightsSection(contexte: ContexteInsights(validation: nil, sport: nil, iob: nil, chargeSynthese: nil))
        // Section vide pour montrer que rien ne s'affiche.
        Section("Suite du formulaire") {
            Text("La section alertes est masquée quand aucun insight n'est disponible.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    .formStyle(.grouped)
}
#endif
