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

                // Pas de `GlassEffectContainer` : il ne sert qu'à fusionner des
                // verres qui se touchent ou s'animent ensemble (morph via
                // `glassEffectID`) — les 3 cartes ont 16pt d'écart et aucune
                // animation partagée. Il cassait par ailleurs le feedback
                // d'appui natif du bouton, obligeant à le reproduire à la
                // main ; sans lui, `.buttonStyle(.plain)` suffit, comme sur
                // la carte « Analyse du coucher ».
                VStack(alignment: .leading, spacing: 16) {
                    // Ombre colorée posée sur le `NavigationLink` lui-même,
                    // pas dans le `label:` (`CarteSection`) : appliquée
                    // dedans, elle se faisait rogner par le système de rendu
                    // du bouton et ne s'affichait jamais — voir
                    // `CarteSection.swift`.
                    NavigationLink(destination: ListeRepasParSection()) {
                        CarteSection(
                            icone: "fork.knife",
                            titre: "Repas",
                            sousTitre: sousTitreRepas,
                            couleur: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .compositingGroup()
                    .shadow(color: Color.blue.opacity(0.45), radius: 16, x: 0, y: 8)

                    NavigationLink(destination: MedicationsVue()) {
                        CarteSection(
                            icone: "syringe",
                            titre: "Médications",
                            sousTitre: sousTitreMedications,
                            couleur: .green
                        )
                    }
                    .buttonStyle(.plain)
                    .compositingGroup()
                    .shadow(color: Color.green.opacity(0.45), radius: 16, x: 0, y: 8)

                    NavigationLink(destination: SportVue()) {
                        CarteSection(
                            icone: "figure.run",
                            titre: "Activités sportives",
                            sousTitre: sousTitreSport,
                            couleur: .orange,
                            badgeImport: importService.aDesImportsEnAttente ? importService.nombreEnAttente : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .compositingGroup()
                    .shadow(color: Color.orange.opacity(0.45), radius: 16, x: 0, y: 8)

                    NavigationLink(destination: ListeResucrages()) {
                        CarteSection(
                            icone: "cross.case",
                            titre: "Resucrage",
                            sousTitre: sousTitreResucrage,
                            couleur: .red
                        )
                    }
                    .buttonStyle(.plain)
                    .compositingGroup()
                    .shadow(color: Color.red.opacity(0.45), radius: 16, x: 0, y: 8)

                    // Même page que Profil → Données : l'inventaire appartient
                    // au corpus, mais le réflexe « où sont mes données » mène
                    // ici, où vivent déjà les quatre familles de faits.
                    NavigationLink(destination: PageInventaireDonnees()) {
                        CarteSection(
                            icone: "externaldrive",
                            titre: "Mes données",
                            sousTitre: "Tout ce qui a été enregistré",
                            couleur: .teal
                        )
                    }
                    .buttonStyle(.plain)
                    .compositingGroup()
                    .shadow(color: Color.teal.opacity(0.45), radius: 16, x: 0, y: 8)
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
}

#if DEBUG
#Preview {
    JournalVue()
        .environment(RepasService.apercu())
        .environment(HealthKitImportService.shared)
}
#endif
