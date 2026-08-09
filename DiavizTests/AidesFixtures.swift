//
//  AidesFixtures.swift
//  DiavizTests
//
//  Fabriques de données partagées par les suites de tests des calculateurs
//  purs. Tout est déterministe et exprimé en instants absolus dérivés d'une
//  seule référence : aucun test ne dépend de `Date()` ni de l'heure de la
//  machine qui exécute la suite.
//

import Foundation
@testable import Diaviz

enum Fixtures {

    /// Instant de référence fixe (1ᵉʳ janvier 2001, 00:00 UTC).
    static let reference = Date(timeIntervalSinceReferenceDate: 0)

    /// Décalage lisible depuis un instant, en minutes.
    static func instant(_ base: Date = reference, plusMinutes minutes: Double) -> Date {
        base.addingTimeInterval(minutes * 60)
    }

    /// Décalage lisible depuis un instant, en heures.
    static func instant(_ base: Date = reference, plusHeures heures: Double) -> Date {
        base.addingTimeInterval(heures * 3600)
    }

    // MARK: - Séries CGM

    /// Série `(date, valeur)` à pas régulier, une entrée par valeur fournie.
    static func serie(
        depuis debut: Date = reference,
        valeurs: [Int],
        pasMinutes: Double = 5
    ) -> [(date: Date, valeur: Int)] {
        valeurs.enumerated().map { index, valeur in
            (date: debut.addingTimeInterval(Double(index) * pasMinutes * 60), valeur: valeur)
        }
    }

    /// Série plate de `nombre` mesures identiques, à pas régulier.
    static func seriePlate(
        depuis debut: Date = reference,
        valeur: Int,
        nombre: Int,
        pasMinutes: Double = 5
    ) -> [(date: Date, valeur: Int)] {
        serie(depuis: debut, valeurs: Array(repeating: valeur, count: nombre), pasMinutes: pasMinutes)
    }

    /// Série linéaire de `nombre` mesures, de `depart` avec une dérive de
    /// `deriveParHeure` mg/dL par heure — sert à fabriquer des pentes exactes.
    static func serieLineaire(
        depuis debut: Date = reference,
        depart: Int,
        deriveParHeure: Double,
        nombre: Int,
        pasMinutes: Double = 5
    ) -> [(date: Date, valeur: Int)] {
        (0..<nombre).map { index in
            let heures = Double(index) * pasMinutes / 60
            return (
                date: debut.addingTimeInterval(Double(index) * pasMinutes * 60),
                valeur: Int((Double(depart) + deriveParHeure * heures).rounded())
            )
        }
    }
}
