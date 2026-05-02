//
//  ListeActivitesSport.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Liste des activités sportives d'un jour. Wrapper autour de la
/// `LigneActiviteSport` qui ajoute :
/// - le swipe gauche "Supprimer" via `.swipeActions`
/// - l'état vide quand le jour n'a pas d'activité
///
/// La navigation au tap est portée par la `LigneActiviteSport` elle-même
/// (`NavigationLink` interne vers `DetailActiviteVue`) — on n'envelopppe
/// donc plus dans un `Button` ici.
///
/// Pas de `List` ici — la vue est consommée à l'intérieur d'une
/// `List` parente (la `SportVue`) pour partager le même style
/// `.insetGrouped` que les autres pages du Journal.
struct ListeActivitesSport: View {

    /// Activités du jour, triées (le tri est de la responsabilité du
    /// service / du parent — on n'en refait pas un ici).
    let activites: [ActiviteSportive]

    /// État de la mini-courbe pour chaque activité, indexé par `id`.
    /// `nil` = données manquantes (la row affichera l'icône warning).
    let etatsCourbes: [UUID: EtatMiniCourbeSport]

    var onSupprimer: (ActiviteSportive) -> Void

    var body: some View {
        if activites.isEmpty {
            etatVide
        } else {
            ForEach(activites) { activite in
                LigneActiviteSport(
                    activite: activite,
                    etatCourbe: etatsCourbes[activite.id] ?? .donneesManquantes
                )
                .id(activite.id)
                // Swipe gauche : suppression native iOS, role .destructive
                // pour la couleur rouge système et le retour haptique.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onSupprimer(activite)
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - État vide
    //
    // `ContentUnavailableView` natif — message + icône SF Symbols. Évite
    // de construire un état custom qui dériverait du style système.
    private var etatVide: some View {
        ContentUnavailableView(
            "Aucune activité",
            systemImage: "figure.run",
            description: Text("Tapez sur + pour enregistrer une activité")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
    }
}
