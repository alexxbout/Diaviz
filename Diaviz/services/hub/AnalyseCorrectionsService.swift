//
//  AnalyseCorrectionsService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service **réel** de l'analyse B3 (corrections du soir) — dérivation
/// branchée sur le hub. Dépend de `AnalyseBasaleService` (B1) pour l'ancrage
/// de nuit (fenêtre de coucher) — cadrage : « B3 dépend de B1 + B2 pour la
/// préparation de données ».
///
/// Convention « un hub, des dérivations » : rien n'est persisté.
@Observable
@MainActor
final class AnalyseCorrectionsService {

    private(set) var analyse: AnalyseCorrections

    /// `true` pendant le recalcul — pilote le loader de la page Analyses.
    private(set) var enCalcul = false

    private var contexte: ModelContext?
    private weak var basale: AnalyseBasaleService?

    var estDemarre: Bool { contexte != nil }

    init() {
        analyse = AnalyseCorrections(corrections: [])
    }

    // MARK: - Boot

    func demarrer(contexte: ModelContext, basale: AnalyseBasaleService) async {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        self.basale = basale
        await recharger()
    }

    /// Lecture et assemblage hors du thread principal (voir
    /// `AnalyseBasaleService.recharger`).
    func recharger() async {
        guard let contexte, let basale else { return }
        enCalcul = true
        let profil = ProfilService.shared.profil
        let config = ConfigCorrections(
            cibleHaute: Int(profil.seuilsGlycemiques.hyperglycemie),
            seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        let nuits = ChargeurFaitsCoucher.ancragesNuit(depuis: basale.analyse.nightChartData)
        let niveauxCharge = ChargeActiveService.shared.contexte?.niveauxParJour ?? [:]
        let entrees = await LecteurHub.lire(container: contexte.container) {
            Self.chargerEntrees(contexte: $0, nuits: nuits, niveauxCharge: niveauxCharge)
        }
        let changementDoseRecent = basale.analyse.changementDoseRecent
        analyse = await Task.detached(priority: .userInitiated) {
            CalculAnalyseCorrections.analyser(
                entrees: entrees, changementDoseRecent: changementDoseRecent, config: config
            )
        }.value
        enCalcul = false
    }

    // MARK: - Accès au hub (fetchs partagés `ChargeurFaitsCoucher`)

    nonisolated private static func chargerEntrees(
        contexte: ModelContext, nuits: [AncrageNuit], niveauxCharge: [Date: NiveauChargeActive]
    ) -> EntreesCorrections {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique()
        let borneCourte = cal.date(byAdding: .day, value: -15, to: debutCourant) ?? debutCourant

        return EntreesCorrections(
            nuits: nuits,
            lectures: ChargeurFaitsCoucher.cgm(contexte, depuis: borneCourte),
            rapides: ChargeurFaitsCoucher.rapides(contexte, depuis: borneCourte),
            repas: ChargeurFaitsCoucher.repasHorsResucrage(contexte, depuis: borneCourte),
            resucrages: ChargeurFaitsCoucher.resucrages(contexte, depuis: borneCourte),
            sports: ChargeurFaitsCoucher.sports(contexte, depuis: borneCourte),
            pauses: ChargeurFaitsCoucher.pauses(contexte, depuis: borneCourte),
            niveauxCharge: niveauxCharge
        )
    }
}
