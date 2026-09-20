//
//  SportVue.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI
import SwiftData

/// Page racine « Activités sportives ». Pushée depuis `JournalVue`
/// via un `NavigationLink`, donc PAS de `NavigationStack` propre —
/// elle hérite de la stack du parent.
///
/// Composition en sections d'une même `List.insetGrouped`, calquée
/// sur `MedicationsVue` :
/// - Section graphe — timeline 24h paginée jour par jour
/// - Section liste — rows tappables, swipe-to-delete
struct SportVue: View {

    // MARK: - État

    /// Contexte du hub SwiftData — passé au service au démarrage de la vue.
    @Environment(\.modelContext) private var modelContext

    @State private var service = ActivitesSportService()
    /// Écrit les resucrages issus des glucides pré-sport saisis avec une
    /// activité — la page Resucrage garde sa propre instance.
    @State private var resucragesService = ResucragesService()

    /// Service de séance chronométrée « en direct » (singleton) — utilisé
    /// ici uniquement pour **démarrer** une séance depuis la sheet de
    /// création. L'écran plein écran de la séance en cours et sa
    /// réconciliation avec la Dynamic Island sont pilotés depuis
    /// `AppTabVues` (racine toujours montée), pas ici : `SportVue` est
    /// poussée via `NavigationLink` et se désalloue dès qu'on la quitte
    /// (retour au Journal, changement d'onglet…), ce qui faisait
    /// disparaître l'écran de séance en cours jusqu'au retour manuel sur
    /// cette page.
    @State private var sessionService = SessionSportService.shared

    /// Service d'import HealthKit — injecté depuis la racine de l'app
    /// via `@Environment`. Observé pour afficher la bannière d'accès
    /// à la sheet d'import en tête de page.
    @Environment(HealthKitImportService.self) private var importService

    /// Date affichée — pilotée par le scroll du graphe et utilisée
    /// pour filtrer la liste en dessous. Représente le début de la
    /// journée (00:00 local).
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Sheet active (création, édition, ou import HealthKit).
    @State private var sheetActive: SheetSport?

    /// Cible du scroll de la liste — alimentée par le tap sur une
    /// barre du graphe pour amener la row correspondante à l'écran.
    @State private var scrollCible: UUID?

    // MARK: - Calculs dérivés

    private var activitesDuJour: [ActiviteSportive] {
        service.activitesDuJour(selectedDate)
    }

    /// Événements corrélés à chaque activité du jour — dérivation à la volée
    /// (fenêtre temporelle), jamais persistée.
    private var evenementsParActivite: [UUID: [EvenementActivite]] {
        Dictionary(uniqueKeysWithValues: activitesDuJour.map { activite in
            (activite.id, service.evenements(pour: activite))
        })
    }

    private var etatsCourbes: [UUID: EtatMiniCourbeSport] {
        Dictionary(uniqueKeysWithValues: activitesDuJour.map { activite in
            let etat: EtatMiniCourbeSport = service.reponse(pour: activite)
                .map { .disponible($0) } ?? .donneesManquantes
            return (activite.id, etat)
        })
    }

    // MARK: - Corps

    var body: some View {
        ScrollViewReader { proxy in
            List {
                sectionGraphe
                sectionImportHealthKit
                sectionListe
            }
            .listStyle(.insetGrouped)
            // Même rythme que les trois autres pages du Journal.
            .listSectionSpacing(24)
            .navigationTitle("Activités sportives")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { boutonAjouter }
            .sheet(item: $sheetActive) { sheet in
                sheetVue(pour: sheet)
            }
            .onChange(of: scrollCible) { _, nouvelle in
                guard let nouvelle else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(nouvelle, anchor: .center)
                }
            }
            .task {
                service.demarrer(contexte: modelContext)
                resucragesService.demarrer(contexte: modelContext)
            }
        }
    }

    // MARK: - Toolbar
    //
    // Bouton "+" en topBarTrailing — ouvre directement la sheet de
    // création (pas de menu intermédiaire, contrairement à la page
    // Médications qui doit choisir entre lente/correction).

    @ToolbarContentBuilder
    private var boutonAjouter: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                sheetActive = .creation
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
            }
            .accessibilityLabel("Ajouter une activité sportive")
        }
    }

    // MARK: - Sections

    /// Section graphe — la row spanne toute la cellule (sans insets)
    /// et utilise un fond transparent : le graphe apporte sa propre
    /// carte englobante (RoundedRectangle + secondarySystemGroupedBackground).
    private var sectionGraphe: some View {
        Section {
            GrapheJourneeSport(
                activites: service.activites,
                selectedDate: $selectedDate,
                onTapActivite: { activite in
                    scrollCible = activite.id
                }
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            TitreSectionListe(texte: "La journée")
        }
    }

    /// Bannière d'accès à la sheet d'import HealthKit. Insérée entre le
    /// graphe et la liste — visible immédiatement, mais pas si proéminente
    /// qu'elle masquerait le graphe ou la liste. Présente uniquement quand
    /// le service signale au moins une activité en attente.
    ///
    /// `listSectionSpacing(8)` resserre l'inter-section au-dessus et
    /// au-dessous du bandeau — sans ça, la `List.insetGrouped` ajoute
    /// par défaut ~35pt de respiration qui font flotter la carte loin
    /// du graphe et de la liste qui l'entourent.
    @ViewBuilder
    private var sectionImportHealthKit: some View {
        if importService.aDesImportsEnAttente {
            Section {
                Button {
                    sheetActive = .importHealthKit
                } label: {
                    bandeauImportHealthKit
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listSectionSpacing(8)
        }
    }

    /// Contenu visuel du bandeau — icône cœur Apple Santé + texte +
    /// chevron. Fond `systemBackground` (blanc en clair, noir en sombre)
    /// pour ressortir nettement du `systemGroupedBackground` de la List.
    ///
    /// Titre fixe « Nouveauté Apple Santé » qui ne dépend pas du
    /// compteur — un titre commençant par un chiffre (« 1 activité… »)
    /// se lisait mal et donnait l'impression d'une simple statistique.
    /// Le compte exact descend en sous-titre, où il joue son rôle
    /// d'information secondaire.
    private var bandeauImportHealthKit: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Nouveauté Apple Santé")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(sousTitreBandeau)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(Color(.systemBackground))
        .clipShape(NiveauCarte.carte.forme)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre la sheet d'import Apple Santé")
    }

    private var sousTitreBandeau: String {
        let n = importService.nombreEnAttente
        if n == 1 { return "Une activité à importer" }
        return "\(n) activités à importer"
    }

    /// Section liste — les rows sont déléguées à `ListeActivitesSport`.
    ///
    /// Le tap sur une row pousse `DetailActiviteVue` via le `NavigationLink`
    /// interne à `LigneActiviteSport` — l'édition se fait depuis ce détail
    /// (menu ⋯), donc plus aucun `onTap` à cabler ici.
    private var sectionListe: some View {
        Section {
            ListeActivitesSport(
                activites: activitesDuJour,
                etatsCourbes: etatsCourbes,
                onEnregistrer: { activite in
                    service.enregistrer(activite)
                },
                onSupprimer: { activite in
                    service.supprimer(activite)
                },
                evenementsParActivite: evenementsParActivite
            )
        } header: {
            TitreSectionListe(texte: "Séances")
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetVue(pour sheet: SheetSport) -> some View {
        switch sheet {
        case .creation:
            SheetNouvelleActivite(
                onValider: { service.enregistrer($0) },
                onDemarrer: { type, structure in sessionService.demarrer(type: type, structureEffort: structure) },
                onCreerResucrages: { resucrages in
                    resucrages.forEach { resucragesService.enregistrer($0) }
                }
            )
        case .importHealthKit:
            SheetImportAppleHealth(
                service: importService,
                // `notifier: false` : la sheet annonce le total du lot en une
                // seule pilule, une par séance serait illisible.
                onImporter: { service.enregistrer($0, notifier: false) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Routage de la sheet

/// Discrimine création et import HealthKit au niveau d'un seul
/// `.sheet(item:)`. L'édition d'une activité existante se fait
/// désormais depuis sa page détail (push) — plus depuis cette page.
/// Enveloppe `Identifiable` d'un brouillon d'activité — `ActiviteSportive`
/// étant un `@Model`, il ne peut pas conformer `Identifiable` directement.
/// Pas `private` : réutilisée par `AppTabVues`, qui pilote désormais la
/// sheet d'enregistrement de fin de séance (voir le commentaire sur
/// `sessionService` plus haut dans ce fichier).
struct BrouillonSession: Identifiable {
    let id = UUID()
    let activite: ActiviteSportive
}

private enum SheetSport: Identifiable {
    case creation
    case importHealthKit

    var id: String {
        switch self {
        case .creation:                "creation"
        case .importHealthKit:         "import-healthkit"
        }
    }
}

// MARK: - Aperçu

// Preview par défaut — montre la bannière d'import « Nouveauté Apple
// Santé » avec deux activités mockées. Mis en premier pour que Xcode
// sélectionne ce rendu à l'ouverture du fichier (l'autre variante,
// sans imports, sert juste à vérifier la dégradation gracieuse).
#if DEBUG
#Preview("Sport - Avec imports") {
    NavigationStack {
        SportVue()
    }
    .modelContainer(ActivitesSportService.conteneurApercu)
    .environment(HealthKitImportService.mockAvecActivites([
        .mockCourse, .mockYoga
    ]))
}

#Preview("Sport - Sans imports") {
    NavigationStack {
        SportVue()
    }
    .modelContainer(ActivitesSportService.conteneurApercu)
    .environment(HealthKitImportService.mockVide())
}
#endif
