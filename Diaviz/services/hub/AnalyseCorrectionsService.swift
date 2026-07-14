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

    private var contexte: ModelContext?
    private weak var basale: AnalyseBasaleService?

    var estDemarre: Bool { contexte != nil }

    init() {
        analyse = AnalyseCorrections(corrections: [])
    }

    // MARK: - Boot

    func demarrer(contexte: ModelContext, basale: AnalyseBasaleService) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        self.basale = basale
        recharger()
    }

    func recharger() {
        guard let contexte, let basale else { return }
        let profil = ProfilService.shared.profil
        let config = ConfigCorrections(
            cibleHaute: Int(profil.seuilsGlycemiques.hyperglycemie),
            seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        analyse = CalculAnalyseCorrections.analyser(
            entrees: chargerEntrees(contexte: contexte, basale: basale),
            changementDoseRecent: basale.analyse.changementDoseRecent,
            config: config
        )
    }

    // MARK: - Accès au hub (fetchs partagés `ChargeurFaitsCoucher`)

    private func chargerEntrees(contexte: ModelContext, basale: AnalyseBasaleService) -> EntreesCorrections {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique()
        let borneCourte = cal.date(byAdding: .day, value: -15, to: debutCourant) ?? debutCourant

        return EntreesCorrections(
            nuits: ChargeurFaitsCoucher.ancragesNuit(depuis: basale.analyse.nightChartData),
            lectures: ChargeurFaitsCoucher.cgm(contexte, depuis: borneCourte),
            rapides: ChargeurFaitsCoucher.rapides(contexte, depuis: borneCourte),
            repas: ChargeurFaitsCoucher.repas(contexte, depuis: borneCourte),
            sports: ChargeurFaitsCoucher.sports(contexte, depuis: borneCourte),
            pauses: ChargeurFaitsCoucher.pauses(contexte, depuis: borneCourte)
        )
    }
}
