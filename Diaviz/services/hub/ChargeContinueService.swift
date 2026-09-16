//
//  ChargeContinueService.swift
//  diaviz
//

import Foundation
import Observation

/// Service **réel** de la charge d'activité continue — cache en mémoire,
/// recalculé sur mutation du hub. Lit les `ActiviteSportive` déjà chargées
/// par la vue appelante (pas de fetch séparé) et délègue à
/// `CalculChargeContinue` (pur).
///
/// Pattern de démarrage aligné sur `GlucidesHebdoService` : `synthese`
/// démarre `nil` tant qu'aucune activité n'a été chargée, mais
/// `CalculChargeContinue.analyser` retourne toujours une série (jamais nil,
/// contrairement aux glucides) — le service reste `nil` uniquement avant le
/// tout premier `recalculer`.
@Observable
@MainActor
final class ChargeContinueService {

    private(set) var synthese: SyntheseChargeContinue?

    func recalculer(depuis activites: [ActiviteSportive]) {
        let entrees = activites.map { (debut: $0.dateDebut, dureeMin: $0.dureeMinutes, intensite: $0.intensite) }
        synthese = CalculChargeContinue.analyser(activites: entrees)
    }
}

#if DEBUG
extension ChargeContinueService {

    @MainActor
    static func apercu(synthese: SyntheseChargeContinue = .mockBaisse) -> ChargeContinueService {
        let service = ChargeContinueService()
        service.synthese = synthese
        return service
    }
}

extension SyntheseChargeContinue {

    /// Semaine tranquille après plusieurs semaines à charge normale —
    /// exerce le badge « en baisse » et le dégradé gris→rouge sur la série.
    static var mockBaisse: SyntheseChargeContinue {
        let cal = Calendar.current
        let aujourdhui = cal.startOfDay(for: Date())
        let scoresRelatifs: [Double] = [
            40, 0, 90, 0, 55, 70, 0,   // J-13 → J-7 : semaine normale
            30, 0, 0, 0, 0, 0, 0,      // J-6 → J0 : quasi rien cette semaine
        ]
        let serie = scoresRelatifs.enumerated().map { index, score in
            PointChargeJour(
                jour: cal.date(byAdding: .day, value: -(13 - index), to: aujourdhui) ?? aujourdhui,
                score: score
            )
        }
        return SyntheseChargeContinue(
            serieJournaliere: serie,
            chargeSemaine: 30,
            normaleHebdo: 260,
            ecartRelatif: -0.88,
            tendance: .enBaisse(jours: 6)
        )
    }
}
#endif
