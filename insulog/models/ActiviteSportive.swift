//
//  ActiviteSportive.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation

/// Une session sportive enregistrée. Modèle volontairement compact —
/// le journal personnel n'a pas vocation à reproduire un tracker GPS.
/// On capture juste ce qui sera nécessaire pour corréler avec la
/// glycémie : type, instant, durée, intensité, glucides éventuels pris
/// en pré-sport.
///
/// `glucidesPreSport` est optionnel : la majorité des séances n'en
/// nécessitent pas, et `nil` est sémantiquement différent de `0` —
/// on ne veut pas afficher « 0g pré-sport » dans la sous-ligne.
struct ActiviteSportive: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let type: TypeSport
    /// Instant de début. La fin se déduit de `dateDebut + dureeMinutes`.
    let dateDebut: Date
    let dureeMinutes: Int
    let intensite: IntensiteSport
    /// Glucides ingérés juste avant l'activité (en grammes). `nil` si
    /// rien de spécifique pris — distingué de la valeur 0.
    let glucidesPreSport: Double?
    let note: String?

    init(
        id: UUID = UUID(),
        type: TypeSport,
        dateDebut: Date,
        dureeMinutes: Int,
        intensite: IntensiteSport,
        glucidesPreSport: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.type = type
        self.dateDebut = dateDebut
        self.dureeMinutes = dureeMinutes
        self.intensite = intensite
        self.glucidesPreSport = glucidesPreSport
        self.note = note
    }
}

extension ActiviteSportive {
    /// Instant de fin de la session — utilisé par la mini-courbe pour
    /// positionner le marqueur « fin » sur l'axe temporel.
    var dateFin: Date {
        dateDebut.addingTimeInterval(TimeInterval(dureeMinutes * 60))
    }
}
