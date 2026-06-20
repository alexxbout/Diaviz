//
//  RepasView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct JournalVue: View {

    /// Service hub des repas, partagé via l'environnement (même instance que la
    /// saisie) → le compteur et la liste reflètent le hub en direct.
    @Environment(RepasService.self) private var repasService

    /// Service d'import HealthKit — injecté depuis la racine de l'app via
    /// `@Environment`. Alimente le badge rouge superposé à la carte « Activités
    /// sportives » quand des workouts sont en attente d'import.
    @Environment(HealthKitImportService.self) private var importService

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Journal")

                VStack(alignment: .leading, spacing: 16) {
                    // `.buttonStyle(.plain)` empêche le `NavigationLink` d'appliquer
                    // sa teinte par défaut, qui surchargerait le blanc/coloré de
                    // notre carte plein fond.
                    NavigationLink(destination: ListeRepasParSection()) {
                        CarteSection(
                            icone: "fork.knife",
                            titre: "Repas",
                            sousTitre: sousTitreRepas,
                            couleur: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: MedicationsVue()) {
                        CarteSection(
                            icone: "syringe",
                            titre: "Médications",
                            sousTitre: "Aucune médication aujourd'hui",
                            couleur: .green
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: SportVue()) {
                        CarteSection(
                            icone: "figure.run",
                            titre: "Activités sportives",
                            sousTitre: "Aucune activité aujourd'hui",
                            couleur: .orange
                        )
                        .overlay(alignment: .topTrailing) { badgeImport }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    /// Sous-titre de la carte « Repas » — compteur du jour, accordé au pluriel.
    private var sousTitreRepas: String {
        let n = repasService.nombreRepasAujourdhui
        return "\(n) repas enregistré\(n > 1 ? "s" : "") aujourd'hui"
    }

    /// Pastille rouge en haut à droite de la carte sport — n'apparaît
    /// que si le service signale des activités à importer. Animation
    /// `easeInOut` pour qu'elle apparaisse/disparaisse en douceur quand
    /// l'utilisateur traite ou ignore depuis la sheet.
    @ViewBuilder
    private var badgeImport: some View {
        if importService.aDesImportsEnAttente {
            Text("\(importService.nombreEnAttente)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red, in: Capsule())
                .padding(12)
                .accessibilityLabel("\(importService.nombreEnAttente) activités Apple Santé à importer")
                .transition(.scale.combined(with: .opacity))
        }
    }
}

#if DEBUG
#Preview {
    JournalVue()
        .environment(RepasService.apercu())
        .environment(HealthKitImportService.shared)
}
#endif
