//
//  RepasView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftData
import SwiftUI

struct JournalVue: View {

    /// Service hub des repas, partagé via l'environnement (même instance que la
    /// saisie) → le compteur et la liste reflètent le hub en direct.
    @Environment(RepasService.self) private var repasService

    /// Service d'import HealthKit — injecté depuis la racine de l'app via
    /// `@Environment`. Alimente le badge rouge superposé à la carte « Activités
    /// sportives » quand des workouts sont en attente d'import.
    @Environment(HealthKitImportService.self) private var importService

    /// Services médications/sport **locaux** — juste pour dériver les
    /// compteurs du jour affichés en sous-titre (les vues détail
    /// `MedicationsVue`/`SportVue` gardent leur propre instance, pas de
    /// partage nécessaire ici). Avant, ces cartes affichaient un texte figé
    /// « Aucune... aujourd'hui » qui ne reflétait jamais le hub.
    @State private var injectionsService = InjectionsService()
    @State private var sportService = ActivitesSportService()

    @Environment(\.modelContext) private var modelContext

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
                            sousTitre: sousTitreMedications,
                            couleur: .green
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: SportVue()) {
                        CarteSection(
                            icone: "figure.run",
                            titre: "Activités sportives",
                            sousTitre: sousTitreSport,
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
        .task {
            injectionsService.demarrer(contexte: modelContext)
            sportService.demarrer(contexte: modelContext)
        }
    }

    /// Sous-titre de la carte « Repas » — compteur du jour, accordé au pluriel.
    private var sousTitreRepas: String {
        let n = repasService.nombreRepasAujourdhui
        return "\(n) repas enregistré\(n > 1 ? "s" : "") aujourd'hui"
    }

    /// Sous-titre de la carte « Médications » — compteur du jour, accordé au
    /// pluriel. Message dédié quand le compteur est à zéro.
    private var sousTitreMedications: String {
        let n = injectionsService.nombreInjectionsAujourdhui
        guard n > 0 else { return "Aucune médication aujourd'hui" }
        return "\(n) médication\(n > 1 ? "s" : "") enregistrée\(n > 1 ? "s" : "") aujourd'hui"
    }

    /// Sous-titre de la carte « Activités sportives » — compteur du jour,
    /// accordé au pluriel. Message dédié quand le compteur est à zéro.
    private var sousTitreSport: String {
        let n = sportService.nombreActivitesAujourdhui
        guard n > 0 else { return "Aucune activité aujourd'hui" }
        return "\(n) activité\(n > 1 ? "s" : "") enregistrée\(n > 1 ? "s" : "") aujourd'hui"
    }

    /// Pastille « à importer » en haut à droite de la carte sport —
    /// n'apparaît que si le service signale des activités Apple Santé en
    /// attente. Pastille **explicite** (icône d'import + compteur +
    /// libellé) plutôt qu'un simple point rouge ambigu : on comprend
    /// d'un coup d'œil qu'il y a N activités à importer dans la section.
    /// Transition `scale + opacity` pour une apparition/disparition douce
    /// quand l'utilisateur traite ou ignore depuis la sheet.
    @ViewBuilder
    private var badgeImport: some View {
        if importService.aDesImportsEnAttente {
            HStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down.fill")
                Text("\(importService.nombreEnAttente) à importer")
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.red, in: Capsule())
            .padding(10)
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
