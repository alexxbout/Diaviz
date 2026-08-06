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

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "fr.al3xdre.diaviz", category: "SessionSport")

    /// Séance en cours, `nil` si aucune. Observé par l'UI (cover plein écran).
    private(set) var session: SessionSportiveEnCours?

    /// Handle de la Live Activity courante (non observable).
    @ObservationIgnored private var activity: Activity<ActiviteSportiveAttributes>?

    var aUneSeanceEnCours: Bool { session != nil }

    private init() {
        session = ControleurSeanceLive.charger()
        if session != nil {
            activity = ControleurSeanceLive.activiteCourante
        }
    }

    // MARK: - Cycle de vie de la séance

    func demarrer(type: TypeSport, structureEffort: StructureEffort? = nil) {
        let nouvelle = SessionSportiveEnCours(type: type, structureEffort: structureEffort)
        session = nouvelle
        ControleurSeanceLive.sauvegarder(nouvelle)
        demarrerActivity(nouvelle)
    }

    func pause() {
        guard let s = session, !s.enPause else { return }
        Task { session = await ControleurSeanceLive.basculerPause() ?? session }
    }

    func reprendre() {
        guard let s = session, s.enPause else { return }
        Task { session = await ControleurSeanceLive.basculerPause() ?? session }
    }

    /// Termine la séance et renvoie un **brouillon** d'`ActiviteSportive`
    /// (durée chronométrée, intensité par défaut) à pré-remplir dans la sheet
    /// d'enregistrement. Ne persiste rien dans le hub — c'est l'appelant qui
    /// confirme la sauvegarde.
    func terminer() -> ActiviteSportive? {
        guard let s = session else { return nil }
        session = nil
        ControleurSeanceLive.effacer()
        ControleurSeanceLive.effacerTerminee()
        activity = nil
        Task { await ControleurSeanceLive.finirActivite() }
        return brouillon(depuis: s)
    }

    /// Abandonne la séance sans rien enregistrer.
    func annuler() {
        session = nil
        ControleurSeanceLive.effacer()
        ControleurSeanceLive.effacerTerminee()
        activity = nil
        Task { await ControleurSeanceLive.finirActivite() }
    }

    // MARK: - Réconciliation au premier plan
    //
    // Les boutons de la Dynamic Island (Pause/Terminer) mutent la séance
    // persistée depuis un `LiveActivityIntent`, hors de cette instance
    // observable. Au retour au premier plan on resynchronise : d'abord une
    // éventuelle séance terminée depuis l'île (→ brouillon à enregistrer),
    // sinon on recharge l'état pause/reprise.

    /// Recharge l'état depuis le store. Renvoie un brouillon si la séance a
    /// été terminée depuis l'île (à enregistrer côté UI), `nil` sinon.
    @discardableResult
    func reconcilier() -> ActiviteSportive? {
        if let terminee = ControleurSeanceLive.chargerTerminee() {
            ControleurSeanceLive.effacerTerminee()
            session = nil
            activity = nil
            return brouillon(depuis: terminee)
        }
        session = ControleurSeanceLive.charger()
        if session != nil, activity == nil {
            activity = ControleurSeanceLive.activiteCourante
        }
        return nil
    }

    // MARK: - Privé

    private func brouillon(depuis s: SessionSportiveEnCours) -> ActiviteSportive {
        // Si la séance se termine pendant une pause encore en cours, cette
        // dernière fenêtre n'est jamais passée par `basculerPause()` (qui ne
        // finalise qu'à la reprise) — on la clôt ici à l'instant présent
        // pour que `pauses` (et donc `dateFin`) reste complet.
        var pauses = s.periodesPauseTerminees
        if let debut = s.debutPauseCourante {
            pauses.append(IntervallePauseSeance(debut: debut, fin: Date()))
        }
        return ActiviteSportive(
            type: s.type,
            dateDebut: s.dateDebut,
            dureeMinutes: s.dureeMinutesArrondie,
            intensite: .moderee,
            structureEffort: s.structureEffort,
            pauses: pauses,
            source: .manuel
        )
    }

    private func demarrerActivity(_ s: SessionSportiveEnCours) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities désactivées — chrono en direct sans Dynamic Island.")
            return
        }
        let attributs = ActiviteSportiveAttributes(
            typeLabel: s.type.rawValue,
            iconeSF: s.type.icone,
            dateDebut: s.dateDebut
        )
        do {
            activity = try Activity.request(
                attributes: attributs,
                content: .init(state: ControleurSeanceLive.etat(s), staleDate: nil)
            )
        } catch {
            logger.error("Démarrage Live Activity impossible : \(error.localizedDescription, privacy: .public)")
        }
    }
}
