//
//  ControleurSeanceLive.swift
//  diaviz
//
//  ⚠️ Fichier PARTAGÉ app ↔ widget (Target Membership sur les deux cibles).
//  Volontairement sans SwiftData ni @Observable : il ne manipule que la
//  `SessionSportiveEnCours` persistée (UserDefaults) et la Live Activity
//  (ActivityKit), pour que les `LiveActivityIntent` des boutons de l'île —
//  qui s'exécutent dans le process de l'app mais dont le type doit compiler
//  dans la cible widget — puissent piloter la séance sans embarquer tout le
//  service applicatif.
//

import Foundation
import ActivityKit

enum ControleurSeanceLive {

    static let cleSession = "sport.session.encours"
    /// Snapshot d'une séance terminée depuis l'île, en attente que l'app
    /// revienne au premier plan pour ouvrir l'enregistrement pré-rempli.
    static let cleTerminee = "sport.session.terminee"

    // MARK: - Persistance

    static func charger() -> SessionSportiveEnCours? {
        guard let data = UserDefaults.standard.data(forKey: cleSession) else { return nil }
        return try? JSONDecoder().decode(SessionSportiveEnCours.self, from: data)
    }

    static func sauvegarder(_ s: SessionSportiveEnCours) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(data, forKey: cleSession)
    }

    static func effacer() {
        UserDefaults.standard.removeObject(forKey: cleSession)
    }

    static func chargerTerminee() -> SessionSportiveEnCours? {
        guard let data = UserDefaults.standard.data(forKey: cleTerminee) else { return nil }
        return try? JSONDecoder().decode(SessionSportiveEnCours.self, from: data)
    }

    static func effacerTerminee() {
        UserDefaults.standard.removeObject(forKey: cleTerminee)
    }

    // MARK: - État Live Activity

    static func etat(_ s: SessionSportiveEnCours) -> ActiviteSportiveAttributes.ContentState {
        .init(
            enPause: s.enPause,
            dateReference: s.dateReference,
            secondesFigees: s.secondesEcoulees()
        )
    }

    /// La Live Activity de séance en cours (au plus une à la fois).
    static var activiteCourante: Activity<ActiviteSportiveAttributes>? {
        Activity<ActiviteSportiveAttributes>.activities.first
    }

    static func majActivite(_ s: SessionSportiveEnCours) async {
        await activiteCourante?.update(ActivityContent(state: etat(s), staleDate: nil))
    }

    static func finirActivite() async {
        await activiteCourante?.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: - Mutations (utilisées par les intents de l'île ET le service app)

    /// Bascule pause ⇄ reprise sur la séance persistée, met à jour la Live
    /// Activity, et renvoie la session mutée (`nil` si aucune séance).
    @discardableResult
    static func basculerPause() async -> SessionSportiveEnCours? {
        guard var s = charger() else { return nil }
        let maintenant = Date()
        if let debut = s.debutPauseCourante {
            s.secondesPauseCumulees += maintenant.timeIntervalSince(debut)
            s.debutPauseCourante = nil
        } else {
            s.debutPauseCourante = maintenant
        }
        sauvegarder(s)
        await majActivite(s)
        return s
    }

    /// Termine la séance : fige un snapshot pour l'enregistrement, efface la
    /// séance active et clôt la Live Activity.
    static func terminer() async {
        guard let s = charger() else { return }
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: cleTerminee)
        }
        effacer()
        await finirActivite()
    }
}
