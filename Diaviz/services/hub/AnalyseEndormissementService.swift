//
//  AnalyseEndormissementService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service **réel** de l'analyse B2 (endormissement / hypos au coucher) —
/// dérivation branchée sur le hub. Dépend de `AnalyseBasaleService` (B1) pour
/// l'ancrage de nuit (lente, glycémie au coucher) — cadrage : « B2 dépend de
/// B1 pour la préparation de données ».
///
/// Convention « un hub, des dérivations » : rien n'est persisté. Le contexte
/// et la référence à B1 sont injectés au boot via `.task { demarrer(...) }` ;
/// `recharger()` recalcule après une ingestion ou un retour sur la page.
@Observable
@MainActor
final class AnalyseEndormissementService {

    private(set) var analyse: AnalyseEndormissement

    /// `true` pendant le recalcul — pilote le loader de la page Analyses.
    private(set) var enCalcul = false

    private var contexte: ModelContext?
    private weak var basale: AnalyseBasaleService?

    var estDemarre: Bool { contexte != nil }

    init() {
        analyse = AnalyseEndormissement(seuilCoucher: ConfigEndormissement().seuilCoucher, doseActuelle: 0, nuits: [])
    }

    // MARK: - Boot

    /// Branche le service sur le hub et sur l'analyse B1 (déjà démarrée et
    /// **attendue** par l'appelant — `basale.analyse` doit être à jour).
    /// Idempotent.
    func demarrer(contexte: ModelContext, basale: AnalyseBasaleService) async {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        self.basale = basale
        await recharger()
    }

    /// Recalcule depuis le hub et depuis l'analyse B1 courante. Idempotent :
    /// à rappeler après une ingestion CGM ou une mise à jour de B1. Le fetch
    /// reste `MainActor` ; l'assemblage pur est déporté (voir `AnalyseBasaleService.recharger`).
    func recharger() async {
        guard let contexte, let basale else { return }
        enCalcul = true
        let profil = ProfilService.shared.profil
        let config = ConfigEndormissement(
            seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        let entrees = chargerEntrees(contexte: contexte, basale: basale)
        let doseActuelle = basale.analyse.doseActuelle
        let changementDoseRecent = basale.analyse.changementDoseRecent
        analyse = await Task.detached(priority: .userInitiated) {
            CalculAnalyseEndormissement.analyser(
                entrees: entrees, doseActuelle: doseActuelle,
                changementDoseRecent: changementDoseRecent, config: config
            )
        }.value
        enCalcul = false
    }

    // MARK: - Accès au hub (fetchs partagés `ChargeurFaitsCoucher`)

    private func chargerEntrees(contexte: ModelContext, basale: AnalyseBasaleService) -> EntreesEndormissement {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique()
        let borneCourte = cal.date(byAdding: .day, value: -15, to: debutCourant) ?? debutCourant

        return EntreesEndormissement(
            nuits: ChargeurFaitsCoucher.ancragesNuit(depuis: basale.analyse.nightChartData),
            lectures: ChargeurFaitsCoucher.cgm(contexte, depuis: borneCourte),
            rapides: ChargeurFaitsCoucher.rapides(contexte, depuis: borneCourte),
            repas: ChargeurFaitsCoucher.repasHorsResucrage(contexte, depuis: borneCourte),
            resucrages: ChargeurFaitsCoucher.resucrages(contexte, depuis: borneCourte),
            sports: ChargeurFaitsCoucher.sports(contexte, depuis: borneCourte),
            pauses: ChargeurFaitsCoucher.pauses(contexte, depuis: borneCourte)
        )
    }
}
