//
//  LecteurHub.swift
//  diaviz
//

import Foundation
import SwiftData

/// Lecture du hub **hors du thread principal**, pour que des dizaines de
/// milliers de mesures CGM ne gèlent plus l'interface (ni la barre d'onglets).
///
/// Règles :
/// - seules des valeurs `Sendable` ressortent, jamais un `@Model` ;
/// - un acteur **neuf par lecture** : son `ModelContext` part vide, il voit
///   donc tout ce qui est enregistré dans le store (saisies, CGM, imports
///   iCloud) sans cache périmé, et libère les objets lus dès la fin ;
/// - créé depuis une tâche détachée : initialisé sur le thread principal, un
///   `@ModelActor` y exécuterait aussi ses lectures.
///
/// Ne voit que ce qui est **enregistré** : à appeler après `save()`.
@ModelActor
actor LecteurHub {

    private func executer<Resultat: Sendable>(
        _ lecture: @Sendable (ModelContext) -> Resultat
    ) -> Resultat {
        return lecture(modelContext)
    }

    /// Exécute `lecture` sur un contexte dédié, hors du thread principal.
    nonisolated static func lire<Resultat: Sendable>(
        container: ModelContainer,
        _ lecture: @escaping @Sendable (ModelContext) -> Resultat
    ) async -> Resultat {
        await Task.detached(priority: .userInitiated) {
            await LecteurHub(modelContainer: container).executer(lecture)
        }.value
    }
}
