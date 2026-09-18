//
//  BilanCorrectionsService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service **réel** du bilan des corrections — toutes heures, indépendant de
/// B1/B3 (aucun ancrage de nuit requis). Convention « un hub, des
/// dérivations » : rien n'est persisté.
@Observable
@MainActor
final class BilanCorrectionsService {

    private(set) var bilan: BilanCorrections

    /// `true` pendant le recalcul — pilote le loader de la page Analyses.
    private(set) var enCalcul = false

    private var contexte: ModelContext?

    var estDemarre: Bool { contexte != nil }

    init() {
        bilan = .vide
    }

    // MARK: - Boot

    func demarrer(contexte: ModelContext) async {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        await recharger()
    }

    func recharger() async {
        guard let contexte else { return }
        enCalcul = true
        let profil = ProfilService.shared.profil
        let config = ConfigBilanCorrections(
            cibleHaute: Int(profil.seuilsGlycemiques.hyperglycemie),
            seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes,
            ratioCorrection: profil.ratioCorrection
        )
        let entrees = chargerEntrees(contexte: contexte)
        bilan = await Task.detached(priority: .userInitiated) {
            CalculBilanCorrections.analyser(entrees: entrees, config: config)
        }.value
        enCalcul = false
    }

    // MARK: - Accès au hub (fetchs partagés `ChargeurFaitsCoucher`)

    private func chargerEntrees(contexte: ModelContext) -> EntreesBilanCorrections {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique()
        // Fenêtre plus large que B3 (15 j) : les corrections diurnes ne sont
        // pas ancrées à une nuit, un historique plus profond reste pertinent
        // tant que le CGM le couvre.
        let borne = cal.date(byAdding: .day, value: -45, to: debutCourant) ?? debutCourant

        return EntreesBilanCorrections(
            lectures: ChargeurFaitsCoucher.cgm(contexte, depuis: borne),
            rapides: ChargeurFaitsCoucher.rapides(contexte, depuis: borne),
            resucrages: ChargeurFaitsCoucher.resucrages(contexte, depuis: borne),
            pauses: ChargeurFaitsCoucher.pauses(contexte, depuis: borne)
        )
    }
}
