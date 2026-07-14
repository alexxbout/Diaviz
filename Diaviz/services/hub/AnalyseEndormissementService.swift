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

    // MARK: - Accès au hub (mapping @Model → value types)

    private func chargerEntrees(contexte: ModelContext, basale: AnalyseBasaleService) -> EntreesEndormissement {
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique()
        let borneCourte = cal.date(byAdding: .day, value: -15, to: debutCourant) ?? debutCourant

        let nuits = ancragesNuit(depuis: basale.analyse.nightChartData)
        let cgm = fetchCGM(contexte, depuis: borneCourte)
        let rapides = fetchRapides(contexte, depuis: borneCourte)
        let repas = fetchRepas(contexte, depuis: borneCourte)
        let sports = fetchSports(contexte, depuis: borneCourte)
        let pauses = fetchPauses(contexte, depuis: borneCourte)

        return EntreesEndormissement(
            nuits: nuits, lectures: cgm, rapides: rapides,
            repas: repas, sports: sports, pauses: pauses
        )
    }

    /// Ancrages dérivés du `NightChartData` déjà calculé par B1 — pas de
    /// nouvelle segmentation, juste une projection des champs stables.
    private func ancragesNuit(depuis nightChartData: [NightChartData]) -> [AncrageNuit] {
        nightChartData.map {
            AncrageNuit(
                dateNuit: $0.date, basaleTime: $0.basaleTime,
                doseLente: $0.basaleDose, glycemieCoucher: Int($0.startGlucose.rounded())
            )
        }
    }

    private func fetchCGM(
        _ contexte: ModelContext, depuis: Date
    ) -> [(date: Date, valeur: Int, tendance: TendanceGlycemie?)] {
        var d = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= depuis },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        d.propertiesToFetch = [\.date, \.valeur, \.tendance]
        return ((try? contexte.fetch(d)) ?? []).map { (date: $0.date, valeur: $0.valeur, tendance: $0.tendance) }
    }

    private func fetchRapides(
        _ contexte: ModelContext, depuis: Date
    ) -> [(heure: Date, dose: Double, correction: Bool)] {
        // Le filtre par type d'enum se fait en Swift (fragile dans un
        // #Predicate), même convention que `AnalyseBasaleService`.
        let d = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.heure >= depuis },
            sortBy: [SortDescriptor(\.heure, order: .forward)]
        )
        return ((try? contexte.fetch(d)) ?? [])
            .filter { $0.type != .lente }
            .map {
                (heure: $0.heure, dose: $0.dose,
                 correction: $0.type == .rapideCorrection || $0.motif == .correction)
            }
    }

    private func fetchRepas(_ contexte: ModelContext, depuis: Date) -> [(heure: Date, glucides: Int)] {
        let d = FetchDescriptor<Repas>(predicate: #Predicate { $0.heure >= depuis })
        return ((try? contexte.fetch(d)) ?? []).map { (heure: $0.heure, glucides: $0.totalGlucides) }
    }

    private func fetchSports(
        _ contexte: ModelContext, depuis: Date
    ) -> [(debut: Date, resume: SportResume)] {
        let d = FetchDescriptor<ActiviteSportive>(predicate: #Predicate { $0.dateDebut >= depuis })
        return ((try? contexte.fetch(d)) ?? []).map {
            (debut: $0.dateDebut,
             resume: SportResume(type: $0.type.rawValue, intensite: $0.intensite.rawValue, dureeMinutes: $0.dureeMinutes))
        }
    }

    private func fetchPauses(_ contexte: ModelContext, depuis: Date) -> [(debut: Date, fin: Date?)] {
        let d = FetchDescriptor<PeriodePause>()
        return ((try? contexte.fetch(d)) ?? [])
            .filter { ($0.fin ?? Date()) >= depuis }
            .map { (debut: $0.debut, fin: $0.fin) }
    }
}
