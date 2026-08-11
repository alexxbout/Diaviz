//
//  GlucidesHebdoService.swift
//  diaviz
//

import Foundation
import Observation

/// Service **réel** de la tendance hebdomadaire de glucides — cache en
/// mémoire, recalculé sur mutation du hub. Lit directement `RepasService.repas`
/// (déjà chargé, pas de fetch SwiftData séparé) et délègue à
/// `CalculGlucidesHebdo` (pur).
///
/// Pattern de démarrage aligné sur `AnalyseRatioService` : `synthese` démarre
/// à `nil` (état « pas assez de données »), recalculé via
/// `recalculer(depuis:)` après chaque mutation connue du hub.
@Observable
@MainActor
final class GlucidesHebdoService {

    private(set) var synthese: SyntheseGlucidesHebdo?

    /// Recalcule depuis les repas déjà chargés par `RepasService` — volume
    /// trivial (agrégation sur 14 jours au grand maximum), pas besoin de
    /// `Task.detached`.
    func recalculer(depuis repas: [Repas]) {
        synthese = CalculGlucidesHebdo.analyser(repas: repas)
    }
}

#if DEBUG
extension GlucidesHebdoService {

    /// Instance de preview peuplée directement (pas de fetch), pour les
    /// vues qui consomment ce service via `@Environment`.
    @MainActor
    static func apercu(synthese: SyntheseGlucidesHebdo? = .mockCroissance) -> GlucidesHebdoService {
        let service = GlucidesHebdoService()
        service.synthese = synthese
        return service
    }
}

extension SyntheseGlucidesHebdo {

    /// 14 jours de démo — glucides en légère hausse cette semaine.
    static var mockCroissance: SyntheseGlucidesHebdo {
        let valeurs = [160, 210, 120, 186, 165, 150, 186, 165, 200, 110, 175, 220, 165, 240]
        let aujourdhui = Calendar.current.startOfDay(for: Date())
        let serie = valeurs.enumerated().map { index, valeur in
            PointGlucidesJour(
                jour: Calendar.current.date(byAdding: .day, value: -(13 - index), to: aujourdhui) ?? aujourdhui,
                totalGlucides: valeur
            )
        }
        return SyntheseGlucidesHebdo(moyenneCetteSemaine: 187, moyenneSemaineDerniere: 173, serieJournaliere: serie)
    }
}
#endif
