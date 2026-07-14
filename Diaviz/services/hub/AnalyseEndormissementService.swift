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

    private var contexte: ModelContext?
    private weak var basale: AnalyseBasaleService?

    var estDemarre: Bool { contexte != nil }

    init() {
        analyse = AnalyseEndormissement(seuilCoucher: ConfigEndormissement().seuilCoucher, doseActuelle: 0, nuits: [])
    }

    // MARK: - Boot

    /// Branche le service sur le hub et sur l'analyse B1 (déjà démarrée par
    /// l'appelant). Idempotent.
    func demarrer(contexte: ModelContext, basale: AnalyseBasaleService) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        self.basale = basale
        recharger()
    }

    /// Recalcule depuis le hub et depuis l'analyse B1 courante. Idempotent :
    /// à rappeler après une ingestion CGM ou une mise à jour de B1.
    func recharger() {
        guard let contexte, let basale else { return }
        let profil = ProfilService.shared.profil
        let config = ConfigEndormissement(
            seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        analyse = CalculAnalyseEndormissement.analyser(
            entrees: chargerEntrees(contexte: contexte, basale: basale),
            doseActuelle: basale.analyse.doseActuelle,
            changementDoseRecent: basale.analyse.changementDoseRecent,
            config: config
        )
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
            repas: ChargeurFaitsCoucher.repas(contexte, depuis: borneCourte),
            sports: ChargeurFaitsCoucher.sports(contexte, depuis: borneCourte),
            pauses: ChargeurFaitsCoucher.pauses(contexte, depuis: borneCourte)
        )
    }
}
