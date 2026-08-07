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

    /// Phase de scène — au retour au premier plan on resynchronise l'état de
    /// séance (les boutons de la Dynamic Island mutent hors de l'app).
    @Environment(\.scenePhase) private var scenePhase

    @State private var service = ActivitesSportService()

    /// Service de séance chronométrée « en direct » (singleton, survit au
    /// relaunch). Observé pour présenter l'écran plein écran quand une séance
    /// tourne — y compris au retour dans l'onglet après un kill de l'app.
    @State private var sessionService = SessionSportService.shared

    /// Brouillon d'activité à enregistrer après l'arrêt d'une séance
    /// chronométrée — pilote la sheet d'enregistrement pré-remplie.
    /// Enveloppé dans un wrapper `Identifiable` car `ActiviteSportive` est un
    /// `@Model` (conformance `Identifiable` explicite impossible : conflit
    /// isolation MainActor / SendableMetatype).
    @State private var brouillonSession: BrouillonSession?

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

    /// Binding vers la séance en cours pour piloter le `fullScreenCover`.
    /// `set` : seule la mise à `nil` (dismiss système) est relayée en abandon
    /// — le service reste la source de vérité pour les transitions internes.
    private var bindingSession: Binding<SessionSportiveEnCours?> {
        Binding(
            get: { sessionService.session },
            set: { nouvelle in if nouvelle == nil { sessionService.annuler() } }
        )
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
            .navigationTitle("Activités sportives")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { boutonAjouter }
            .sheet(item: $sheetActive) { sheet in
                sheetVue(pour: sheet)
            }
            .sheet(item: $brouillonSession) { brouillon in
                SheetNouvelleActivite(
                    preremplissage: brouillon.activite,
                    onValider: { service.enregistrer($0) }
                )
            }
            .fullScreenCover(item: bindingSession) { session in
                SeanceEnCoursVue(
                    session: session,
                    onTerminer: { brouillon in brouillonSession = BrouillonSession(activite: brouillon) },
                    onAnnuler: { sessionService.annuler() }
                )
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                if let brouillon = sessionService.reconcilier() {
                    brouillonSession = BrouillonSession(activite: brouillon)
                }
            }
            .onChange(of: scrollCible) { _, nouvelle in
                guard let nouvelle else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(nouvelle, anchor: .center)
                }
            }
            .task { service.demarrer(contexte: modelContext) }
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre la sheet d'import Apple Santé")
    }

    private var sousTitreBandeau: String {
        let n = importService.nombreEnAttente
        if n == 1 { return "Une activité à importer" }
        return "\(n) activités à importer"
    }

    /// Section liste — pas de header (le libellé du jour est déjà
    /// porté par l'en-tête du graphe juste au-dessus). Les rows sont
    /// déléguées à `ListeActivitesSport`.
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
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetVue(pour sheet: SheetSport) -> some View {
        switch sheet {
        case .creation:
            SheetNouvelleActivite(
                onValider: { service.enregistrer($0) },
                onDemarrer: { type, structure in sessionService.demarrer(type: type, structureEffort: structure) }
            )
        case .importHealthKit:
            SheetImportAppleHealth(
                service: importService,
                onImporter: { service.enregistrer($0) }
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
private struct BrouillonSession: Identifiable {
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
