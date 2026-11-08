//
//  SessionSportiveEnCours.swift
//  diaviz
//

import Foundation

/// Séance sportive **en cours de chronométrage** — état volatil d'une
/// activité démarrée « en direct » depuis la sheet, tant qu'elle n'est pas
/// terminée et transformée en `ActiviteSportive` persistée dans le hub.
///
/// `Codable` pour être sérialisée en `UserDefaults` : une séance doit
/// survivre à un kill/relaunch de l'app (l'utilisateur peut fermer Diaviz
/// pendant qu'il court). `Identifiable` pour piloter un `fullScreenCover`.
///
/// La gestion de la pause n'arrête pas d'horloge : on cumule le temps passé
/// en pause (`secondesPauseCumulees`) et on mémorise le début de la pause
/// courante (`debutPauseCourante`). Le temps d'effort réel se recalcule à la
/// volée depuis ces deux valeurs — aucun timer à faire tourner en tâche de
/// fond, tout se déduit des horodatages.
nonisolated struct SessionSportiveEnCours: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let type: TypeSport
    /// Instant de démarrage (absolu).
    let dateDebut: Date
    /// Structure de l'effort déclarée au démarrage (continu/fractionné) —
    /// pertinent uniquement pour `CategorieSport.cardio`. Choisie avant le
    /// lancement du chrono, pas déductible après coup.
    let structureEffort: StructureEffort?
    /// Temps total déjà passé en pause avant la pause courante. Reste la
    /// source de vérité pour le calcul du temps d'effort — `periodesPauseTerminees`
    /// est un journal parallèle, purement additif, jamais relu pour le chrono.
    var secondesPauseCumulees: TimeInterval
    /// Début de la pause en cours, `nil` si la séance tourne.
    var debutPauseCourante: Date?
    /// Fenêtres `[début, fin]` des pauses déjà terminées — journal détaillé
    /// en plus du cumul. Alimente le signal « resucrage pendant une pause »
    /// et la correction de `ActiviteSportive.dateFin` (voir doc Eraser S1).
    var periodesPauseTerminees: [IntervallePauseSeance]

    init(
        id: UUID = UUID(),
        type: TypeSport,
        dateDebut: Date = Date(),
        structureEffort: StructureEffort? = nil,
        secondesPauseCumulees: TimeInterval = 0,
        debutPauseCourante: Date? = nil,
        periodesPauseTerminees: [IntervallePauseSeance] = []
    ) {
        self.id = id
        self.type = type
        self.dateDebut = dateDebut
        self.structureEffort = structureEffort
        self.secondesPauseCumulees = secondesPauseCumulees
        self.debutPauseCourante = debutPauseCourante
        self.periodesPauseTerminees = periodesPauseTerminees
    }

    var enPause: Bool { debutPauseCourante != nil }

    /// Date de référence pour un timer **count-up** (`Text(_, style: .timer)`) :
    /// le début décalé de tout le temps de pause cumulé, de sorte que
    /// `maintenant − dateReference` égale le temps d'effort réel écoulé.
    /// Valable uniquement quand la séance tourne (hors pause).
    var dateReference: Date {
        dateDebut.addingTimeInterval(secondesPauseCumulees)
    }

    /// Temps d'effort réel écoulé (pauses déduites), à l'instant donné.
    func secondesEcoulees(a maintenant: Date = Date()) -> TimeInterval {
        let pauseCourante = debutPauseCourante.map { maintenant.timeIntervalSince($0) } ?? 0
        return max(0, maintenant.timeIntervalSince(dateDebut) - secondesPauseCumulees - pauseCourante)
    }

    /// Durée arrondie à la minute, plancher à 1 — pour pré-remplir la sheet
    /// d'enregistrement à la fin de la séance.
    var dureeMinutesArrondie: Int {
        max(1, Int((secondesEcoulees() / 60).rounded()))
    }
}
