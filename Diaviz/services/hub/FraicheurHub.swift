//
//  FraicheurHub.swift
//  diaviz
//

import Foundation
import SwiftData

/// Compteur qui avance à chaque changement du hub : enregistrement d'un
/// contexte (saisie, profil, CGM, import Santé) ou réception iCloud.
///
/// Permet à une page de savoir, sans rien relire, si le dernier résultat
/// affiché est encore bon.
@MainActor
final class FraicheurHub {

    static let shared = FraicheurHub()

    private(set) var revision = 0
    private var observateur: (any NSObjectProtocol)?

    private init() {
        observateur = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.signalerChangement() }
        }
    }

    func signalerChangement() {
        revision += 1
    }

    /// État courant du hub et de la charge, à poser au lancement d'un calcul.
    func marqueur(maintenant: Date = Date()) -> MarqueurFraicheur {
        MarqueurFraicheur(
            revisionHub: revision,
            revisionCharge: ChargeActiveService.shared.revisionContexte,
            instant: maintenant
        )
    }
}

/// Ce sur quoi un résultat a été calculé. Il reste valable tant que ni le
/// hub ni la charge n'ont changé, et au plus `dureeValidite` : les fenêtres
/// d'analyse glissent avec l'heure, même sans nouvelle donnée.
nonisolated struct MarqueurFraicheur: Equatable, Sendable {

    static let dureeValidite: TimeInterval = 15 * 60

    let revisionHub: Int
    let revisionCharge: Int
    let instant: Date

    func resteValable(par courant: MarqueurFraicheur) -> Bool {
        let age = courant.instant.timeIntervalSince(instant)
        return revisionHub == courant.revisionHub
            && revisionCharge == courant.revisionCharge
            && age >= 0
            && age < Self.dureeValidite
    }
}
