//
//  InsightsSection.swift
//  insulog
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
/// Ordre de priorité d'affichage :
/// 1. ValidationRatioCard (vert / orange / rouge selon état)
/// 2. SportDetecteCard (bleu)
/// 3. IOBCard (indigo)
struct InsightsSection: View {

    let contexte: ContexteInsights

    @State private var afficherInfo: Bool = false

    var body: some View {
        if aucunInsight {
            EmptyView()
        } else {
            Section {
                VStack(spacing: 10) {
                    if let validation = contexte.validation {
                        ValidationRatioCard(validation: validation)
                    }
                    if let sport = contexte.sport {
                        SportDetecteCard(sport: sport)
                    }
                    if let iob = contexte.iob {
                        IOBCard(iob: iob)
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
