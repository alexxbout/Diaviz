//
//  SportVue.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

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

    @State private var service = ActivitesSportServiceMock.shared

    /// Date affichée — pilotée par le scroll du graphe et utilisée
    /// pour filtrer la liste en dessous. Représente le début de la
    /// journée (00:00 local).
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Sheet active (création ou édition).
    @State private var sheetActive: SheetSport?

    /// Cible du scroll de la liste — alimentée par le tap sur une
    /// barre du graphe pour amener la row correspondante à l'écran.
    @State private var scrollCible: UUID?

    // MARK: - Calculs dérivés

    private var activitesDuJour: [ActiviteSportive] {
        service.activitesDuJour(selectedDate)
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
                sectionListe
            }
            .listStyle(.insetGrouped)
            .toolbar(.hidden, for: .tabBar)
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

    /// Section liste — pas de header (le libellé du jour est déjà
    /// porté par l'en-tête du graphe juste au-dessus). Les rows sont
    /// déléguées à `ListeActivitesSport`.
    private var sectionListe: some View {
        Section {
            ListeActivitesSport(
                activites: activitesDuJour,
                etatsCourbes: etatsCourbes,
                onTap: { activite in
                    sheetActive = .edition(activite)
                },
                onSupprimer: { activite in
                    service.supprimer(activite)
                }
            )
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetVue(pour sheet: SheetSport) -> some View {
        switch sheet {
        case .creation:
            SheetNouvelleActivite(onValider: { service.ajouter($0) })
        case .edition(let activite):
            SheetNouvelleActivite(
                activiteExistante: activite,
                onValider: { nouvelleVersion in
                    // Mock : on supprime puis on rajoute. Sur le backend
                    // réel ce sera un PATCH avec l'id existant.
                    service.supprimer(activite)
                    service.ajouter(nouvelleVersion)
                }
            )
        }
    }
}

// MARK: - Routage de la sheet

/// Discrimine création et édition au niveau d'un seul `.sheet(item:)`,
/// pour éviter les conflits de présentation avec deux modificateurs
/// `.sheet` parallèles.
private enum SheetSport: Identifiable {
    case creation
    case edition(ActiviteSportive)

    var id: String {
        switch self {
        case .creation:                "creation"
        case .edition(let a):          "edition-\(a.id.uuidString)"
        }
    }
}

// MARK: - Aperçu

#Preview {
    NavigationStack {
        SportVue()
    }
}
