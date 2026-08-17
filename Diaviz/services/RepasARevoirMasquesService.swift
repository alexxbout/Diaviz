//
//  RepasARevoirMasquesService.swift
//  diaviz
//

import Foundation
import SwiftData

/// Repas « à revoir » masqués par l'utilisateur (long press → confirmation).
///
/// Masque par **occurrence précise** (`RepasARevoir.idRepasSource`, l'id du
/// vrai `Repas` SwiftData qui a motivé la carte), jamais par groupe/signature :
/// si ce même repas se reproduit avec un nouveau mauvais résultat, le
/// "dernier" du groupe devient un nouveau `Repas` (nouvel id, absent de ce
/// set) et la carte réapparaît d'elle-même — voir `CalculRepasARevoir.analyser`.
///
/// Persisté dans le hub SwiftData (`RepasARevoirMasque`), donc synchronisé
/// par CloudKit : une carte écartée sur un appareil ne revient pas sur un
/// autre, et le masquage survit à une réinstallation.
@Observable
final class RepasARevoirMasquesService {
    static let shared = RepasARevoirMasquesService()

    private(set) var idsMasques: Set<UUID> = []

    private var contexte: ModelContext?

    private init() {}

    /// Branche le service sur le hub et charge l'état. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    /// Recharge depuis le store — appelé après un import CloudKit.
    func recharger() {
        guard let contexte else { return }
        let lignes = (try? contexte.fetch(FetchDescriptor<RepasARevoirMasque>())) ?? []
        idsMasques = Set(lignes.map(\.idRepas))
    }

    // MARK: - API

    func masquer(_ id: UUID) {
        guard !idsMasques.contains(id) else { return }
        idsMasques.insert(id)
        guard let contexte else { return }
        contexte.insert(RepasARevoirMasque(idRepas: id))
        try? contexte.save()
    }

    /// Réglages → « Supprimer les repas masqués ». Volontairement pas de
    /// liste consultable (pas demandé) : juste un reset global.
    func toutDemasquer() {
        idsMasques = []
        guard let contexte else { return }
        // Suppression objet par objet, jamais `delete(model:)` : un batch
        // delete n'est pas exporté vers CloudKit, les masquages
        // réapparaîtraient à la synchronisation suivante.
        let lignes = (try? contexte.fetch(FetchDescriptor<RepasARevoirMasque>())) ?? []
        for ligne in lignes {
            contexte.delete(ligne)
        }
        try? contexte.save()
    }
}
