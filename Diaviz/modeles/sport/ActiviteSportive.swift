//
//  ActiviteSportive.swift
//  diaviz
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
    /// Provenance de la saisie. Défaut `.manuel` pour conserver la
    /// compatibilité avec toutes les activités créées avant l'arrivée
    /// du flux d'import HealthKit.
    let source: SourceActivite
    /// Snapshot des métriques HealthKit conservées à l'import. `nil`
    /// pour toute activité dont `source` n'est pas `.healthKit`.
    let healthKitData: HealthKitWorkoutData?
    /// Insuline rapide encore active (« on board ») au démarrage de
    /// l'activité, en unités. Information critique pour un diabétique :
    /// commencer une séance avec beaucoup d'IOB augmente fortement le
    /// risque d'hypoglycémie pendant l'effort. `nil` quand l'info n'a
    /// pas été calculée (legacy ou import sans corrélation avec les
    /// bolus récents).
    let iobAuDebut: Double?

    init(
        id: UUID = UUID(),
        type: TypeSport,
        dateDebut: Date,
        dureeMinutes: Int,
        intensite: IntensiteSport,
        glucidesPreSport: Double? = nil,
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
        self.glucidesPreSport = glucidesPreSport
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
}
