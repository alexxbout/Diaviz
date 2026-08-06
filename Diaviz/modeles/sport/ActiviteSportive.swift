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
    /// Fenêtres de pause de la séance live — vide pour une activité saisie
    /// manuellement ou importée (pas de notion de pause hors chrono direct).
    /// Sert à corriger `dateFin` et à situer un resucrage pendant une pause.
    ///
    /// **Valeur par défaut obligatoire** : sans elle, SwiftData ne sait pas
    /// migrer les activités déjà en base et recrée le store à vide au premier
    /// lancement suivant (constaté le 2026-08-06). Tout nouvel attribut
    /// non-optionnel d'un `@Model` doit porter un défaut — cf. aussi
    /// `Aliment.resucrage`.
    var pauses: [IntervallePauseSeance] = []
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
        pauses: [IntervallePauseSeance] = [],
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
        self.pauses = pauses
        self.note = note
        self.source = source
        self.healthKitData = healthKitData
        self.iobAuDebut = iobAuDebut
    }
}

extension ActiviteSportive {
    /// Instant de fin en horloge murale — utilisé par la mini-courbe pour
    /// positionner le marqueur « fin » sur l'axe temporel, et par toute
    /// future fenêtre de corrélation temporelle (CGM, resucrage, correction).
    ///
    /// `dureeMinutes` est la durée d'**effort net** (pauses déjà déduites,
    /// cf. `SessionSportiveEnCours.dureeMinutesArrondie`) — sans réintégrer
    /// le temps de pause, `dateFin` sous-estimait la fin réelle pour toute
    /// séance ayant eu au moins une pause (point de vigilance identifié lors
    /// du cadrage S1, corrigé ici une fois `pauses` disponible).
    var dateFin: Date {
        let dureeEffort = TimeInterval(dureeMinutes * 60)
        let dureePauses = pauses.reduce(0) { $0 + $1.duree }
        return dateDebut.addingTimeInterval(dureeEffort + dureePauses)
    }

    /// Total des glucides pré-sport (g), somme de `alimentsPreSport`. `0` si
    /// aucun aliment — les appelants distinguent l'affichage vide eux-mêmes
    /// (`0` n'est jamais montré comme « 0g pré-sport »).
    var glucidesPreSportTotal: Double {
        alimentsPreSport.reduce(0) { $0 + Double($1.glucides) }
    }
}
