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

    /// Resucrages lus en `@Query` plutôt que via un service local : un
    /// resucrage peut être écrit depuis la page dédiée **ou** depuis l'écran
    /// de séance live, chacun avec sa propre instance de `ResucragesService`.
    /// Une instance locale ici ne verrait jamais ces écritures (`.task` ne
    /// rejoue pas, `.onAppear` du `NavigationStack` racine non plus au retour
    /// d'un push). `@Query` observe le store directement — toujours à jour,
    /// quel que soit l'écrivain.
    @Query private var resucrages: [Resucrage]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Journal")

                // `GlassEffectContainer` : blend cohérent du Liquid Glass des
                // trois cartes (iOS 26). Cartes à hauteur intrinsèque, groupe
                // aligné en haut sous l'en-tête (pattern standard iOS) — le
                // `Spacer` en dessous absorbe l'espace restant sans pousser
                // le contenu à un centrage artificiel.
                GlassEffectContainer(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        // `.buttonStyle(.plain)` empêche le `NavigationLink` d'appliquer
                        // sa teinte par défaut, qui surchargerait le coloré de la carte.
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

                        NavigationLink(destination: ListeResucrages()) {
                            CarteSection(
                                icone: "cross.case",
                                titre: "Resucrage",
                                sousTitre: sousTitreResucrage,
                                couleur: .red
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)

                Spacer(minLength: 0)
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

    /// Sous-titre de la carte « Resucrage » — compteur du jour, accordé au
    /// pluriel. Message dédié quand le compteur est à zéro.
    private var sousTitreResucrage: String {
        let cal = Calendar.current
        let n = resucrages.count { cal.isDateInToday($0.date) }
        guard n > 0 else { return "Aucun resucrage aujourd'hui" }
        return "\(n) resucrage\(n > 1 ? "s" : "") aujourd'hui"
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
