//
//  ActiviteSportive.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation
import SwiftData

/// Une session sportive enregistrée dans le hub. Modèle volontairement compact —
/// le journal personnel n'a pas vocation à reproduire un tracker GPS. On capture
/// ce qui sert à corréler avec la glycémie : type, instant, durée, intensité,
/// glucides éventuels pris en pré-sport.
///
/// **Fait brut horodaté** (`@Model`) : écrit par la saisie manuelle et par
/// l'ingestion des workouts HealthKit. `alimentsPreSport` vide sémantiquement
/// différent de « non renseigné » n'existe pas ici — une liste vide veut
/// simplement dire qu'aucun aliment n'a été ajouté.
@Model
final class ActiviteSportive {
    var id: UUID
    var type: TypeSport
    /// Instant de début (absolu). La fin se déduit de `dateDebut + dureeMinutes`.
    var dateDebut: Date
    var dureeMinutes: Int
    var intensite: IntensiteSport
    /// Aliments ingérés juste avant l'activité — recherche aliment (même
    /// moteur que la saisie repas), remplace l'ancien champ grammes seul.
    /// Liste vide si rien de spécifique pris.
    @Relationship(deleteRule: .cascade) var alimentsPreSport: [Aliment]
    /// Structure de l'effort (continu/fractionné) — pertinent uniquement pour
    /// `CategorieSport.cardio`, `nil` sinon (musculation/yoga/autre).
    var structureEffort: StructureEffort?
    var note: String?
    /// Provenance de la saisie (manuelle vs import HealthKit).
    var source: SourceActivite
    /// Snapshot des métriques HealthKit conservées à l'import. `nil` hors `.healthKit`.
    var healthKitData: HealthKitWorkoutData?
    /// Insuline rapide encore active au démarrage de l'activité (unités). `nil`
    /// quand l'info n'a pas été calculée (legacy ou import sans corrélation).
    var iobAuDebut: Double?

    init(
        id: UUID = UUID(),
        type: TypeSport,
        dateDebut: Date,
        dureeMinutes: Int,
        intensite: IntensiteSport,
        alimentsPreSport: [Aliment] = [],
        structureEffort: StructureEffort? = nil,
        note: String? = nil,
        source: SourceActivite = .manuel,
        healthKitData: HealthKitWorkoutData? = nil,
        iobAuDebut: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.dateDebut = dateDebut
        self.dureeMinutes = dureeMinutes
        self.intensite = intensite
        self.alimentsPreSport = alimentsPreSport
        self.structureEffort = structureEffort
        self.note = note
        self.source = source
        self.healthKitData = healthKitData
        self.iobAuDebut = iobAuDebut
    }
}

extension ActiviteSportive {
    /// Instant de fin de la session — utilisé par la mini-courbe pour
    /// positionner le marqueur « fin » sur l'axe temporel.
    var dateFin: Date {
        dateDebut.addingTimeInterval(TimeInterval(dureeMinutes * 60))
    }

    /// Total des glucides pré-sport (g), somme de `alimentsPreSport`. `0` si
    /// aucun aliment — les appelants distinguent l'affichage vide eux-mêmes
    /// (`0` n'est jamais montré comme « 0g pré-sport »).
    var glucidesPreSportTotal: Double {
        alimentsPreSport.reduce(0) { $0 + Double($1.glucides) }
    }
}
