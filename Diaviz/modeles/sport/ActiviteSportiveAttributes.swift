//
//  ActiviteSportiveAttributes.swift
//  diaviz
//
//  ⚠️ Fichier PARTAGÉ entre la cible app `Diaviz` et la cible widget
//  extension (Live Activity). Il doit appartenir aux DEUX cibles dans
//  Xcode (Target Membership). Volontairement autonome : il n'importe que
//  `ActivityKit` et ne référence aucun type métier (`TypeSport`, etc.), pour
//  que le widget reste léger et n'ait pas à embarquer tout le modèle. Le
//  libellé et le SF Symbol du sport sont passés en `String`.
//

import ActivityKit
import Foundation

/// Attributs (partie **statique**) d'une Live Activity de séance sportive.
nonisolated struct ActiviteSportiveAttributes: ActivityAttributes {

    /// État **dynamique** poussé à chaque mise à jour de la Live Activity.
    struct ContentState: Codable, Hashable {
        /// La séance est en pause (chrono figé) plutôt qu'en cours.
        var enPause: Bool
        /// Date de référence d'un timer count-up (`Text(_, style: .timer)`) :
        /// début décalé du temps de pause cumulé. Utilisée quand la séance
        /// tourne — le système anime le chrono seul, sans réveiller l'app.
        var dateReference: Date
        /// Temps d'effort figé (secondes) à afficher pendant une pause, où le
        /// timer automatique n'a pas de sens.
        var secondesFigees: TimeInterval
    }

    /// Libellé du sport, ex. « Course ».
    var typeLabel: String
    /// Nom du SF Symbol du sport, ex. « figure.run ».
    var iconeSF: String
    /// Instant de démarrage — affiché « démarré à HH'h'mm » dans l'île.
    var dateDebut: Date
}
