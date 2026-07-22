//
//  SessionSportService.swift
//  diaviz
//

import Foundation
import Observation
import OSLog
import ActivityKit

/// Orchestre une séance sportive chronométrée « en direct » : démarrage,
/// pause/reprise, arrêt. Singleton `@MainActor @Observable` (état d'UI
/// partagé, comme `HealthKitImportService`).
///
/// **Survit au relaunch** : la session courante est sérialisée en
/// `UserDefaults` à chaque mutation et rechargée au boot — l'utilisateur
/// peut fermer l'app pendant l'effort sans perdre le chrono. À l'init on
/// se rebranche aussi sur la Live Activity encore vivante côté système.
///
/// **Live Activity / Dynamic Island** : démarrée à `demarrer(type:)`, mise à
/// jour à chaque pause/reprise, terminée à l'arrêt. Le rendu (île dynamique,
/// écran verrouillé) vit dans la cible widget extension — ce service ne fait
/// que piloter le cycle de vie via ActivityKit.
@MainActor
@Observable
final class SessionSportService {

    static let shared = SessionSportService()

    private let cle = "sport.session.encours"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "fr.al3xdre.diaviz", category: "SessionSport")

    /// Séance en cours, `nil` si aucune. Observé par l'UI (cover plein écran).
    private(set) var session: SessionSportiveEnCours?

    /// Handle de la Live Activity courante (non observable).
    @ObservationIgnored private var activity: Activity<ActiviteSportiveAttributes>?

    var aUneSeanceEnCours: Bool { session != nil }

    private init() {
        session = charger()
        if let session {
            reconnecterActivity(pour: session)
        }
    }

    // MARK: - Cycle de vie de la séance

    func demarrer(type: TypeSport) {
        let nouvelle = SessionSportiveEnCours(type: type)
        session = nouvelle
        sauvegarder(nouvelle)
        demarrerActivity(nouvelle)
    }

    func pause() {
        guard var s = session, !s.enPause else { return }
        s.debutPauseCourante = Date()
        appliquer(s)
    }

    func reprendre() {
        guard var s = session, let debut = s.debutPauseCourante else { return }
        s.secondesPauseCumulees += Date().timeIntervalSince(debut)
        s.debutPauseCourante = nil
        appliquer(s)
    }

    /// Termine la séance et renvoie un **brouillon** d'`ActiviteSportive`
    /// (durée chronométrée, intensité par défaut) à pré-remplir dans la sheet
    /// d'enregistrement. Ne persiste rien dans le hub — c'est l'appelant qui
    /// confirme la sauvegarde.
    func terminer() -> ActiviteSportive? {
        guard let s = session else { return nil }
        let brouillon = ActiviteSportive(
            type: s.type,
            dateDebut: s.dateDebut,
            dureeMinutes: s.dureeMinutesArrondie,
            intensite: .moderee,
            source: .manuel
        )
        nettoyer()
        return brouillon
    }

    /// Abandonne la séance sans rien enregistrer.
    func annuler() {
        nettoyer()
    }

    // MARK: - Privé — mutation + persistance

    private func appliquer(_ s: SessionSportiveEnCours) {
        session = s
        sauvegarder(s)
        majActivity(s)
    }

    private func nettoyer() {
        session = nil
        UserDefaults.standard.removeObject(forKey: cle)
        finirActivity()
    }

    private func sauvegarder(_ s: SessionSportiveEnCours) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(data, forKey: cle)
    }

    private func charger() -> SessionSportiveEnCours? {
        guard let data = UserDefaults.standard.data(forKey: cle) else { return nil }
        return try? JSONDecoder().decode(SessionSportiveEnCours.self, from: data)
    }

    // MARK: - Privé — Live Activity

    private func etat(_ s: SessionSportiveEnCours) -> ActiviteSportiveAttributes.ContentState {
        .init(
            enPause: s.enPause,
            dateReference: s.dateReference,
            secondesFigees: s.secondesEcoulees()
        )
    }

    private func demarrerActivity(_ s: SessionSportiveEnCours) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities désactivées — chrono en direct sans Dynamic Island.")
            return
        }
        let attributs = ActiviteSportiveAttributes(typeLabel: s.type.rawValue, iconeSF: s.type.icone)
        do {
            activity = try Activity.request(
                attributes: attributs,
                content: .init(state: etat(s), staleDate: nil)
            )
        } catch {
            logger.error("Démarrage Live Activity impossible : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func majActivity(_ s: SessionSportiveEnCours) {
        let contenu = ActivityContent(state: etat(s), staleDate: nil)
        Task { await activity?.update(contenu) }
    }

    private func finirActivity() {
        let handle = activity
        activity = nil
        Task { await handle?.end(nil, dismissalPolicy: .immediate) }
    }

    /// Rebranche le service sur une Live Activity encore vivante après un
    /// relaunch (l'app a été tuée mais le système garde l'activité).
    private func reconnecterActivity(pour s: SessionSportiveEnCours) {
        activity = Activity<ActiviteSportiveAttributes>.activities.first
    }
}
