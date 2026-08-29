//
//  ChargeurFaitsCoucher.swift
//  diaviz
//

import Foundation
import SwiftData

/// Fetchs du hub **partagés** par les services des analyses du coucher
/// (`AnalyseEndormissementService`, `AnalyseCorrectionsService`) — mêmes
/// tranches, même mapping @Model → value types. Évite deux copies conformes
/// des mêmes descripteurs.
///
/// `@MainActor` : manipule un `ModelContext` (non-Sendable), appelé depuis
/// les services eux-mêmes MainActor.
@MainActor
enum ChargeurFaitsCoucher {

    /// Ancrages dérivés du `NightChartData` déjà calculé par B1 — pas de
    /// nouvelle segmentation, juste une projection des champs stables.
    static func ancragesNuit(depuis nightChartData: [NightChartData]) -> [AncrageNuit] {
        nightChartData.map {
            AncrageNuit(
                dateNuit: $0.date, basaleTime: $0.basaleTime,
                doseLente: $0.basaleDose, glycemieCoucher: Int($0.startGlucose.rounded())
            )
        }
    }

    static func cgm(
        _ contexte: ModelContext, depuis: Date
    ) -> [(date: Date, valeur: Int, tendance: TendanceGlycemie?)] {
        var d = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= depuis },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        d.propertiesToFetch = [\.date, \.valeur, \.tendance]
        return ((try? contexte.fetch(d)) ?? []).map { (date: $0.date, valeur: $0.valeur, tendance: $0.tendance) }
    }

    static func lentes(
        _ contexte: ModelContext, depuis: Date
    ) -> [(heure: Date, dose: Double)] {
        let d = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.heure >= depuis },
            sortBy: [SortDescriptor(\.heure, order: .forward)]
        )
        return ((try? contexte.fetch(d)) ?? [])
            .filter { $0.type == .lente }
            .map { (heure: $0.heure, dose: $0.dose) }
    }

    static func rapides(
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

    static func repas(_ contexte: ModelContext, depuis: Date) -> [(heure: Date, glucides: Int)] {
        let d = FetchDescriptor<Repas>(predicate: #Predicate { $0.heure >= depuis })
        return ((try? contexte.fetch(d)) ?? []).map { (heure: $0.heure, glucides: $0.totalGlucides) }
    }

    /// Repas **hors resucrages** — un repas dont tous les aliments portent le
    /// badge `resucrage` est un resucrage déguisé (chemin de saisie secondaire,
    /// même règle que `CalculRepasARevoir`). Il sort d'ici pour ne pas être
    /// compté deux fois par les analyses qui consomment aussi `resucrages`.
    static func repasHorsResucrage(
        _ contexte: ModelContext, depuis: Date
    ) -> [(heure: Date, glucides: Int)] {
        let d = FetchDescriptor<Repas>(predicate: #Predicate { $0.heure >= depuis })
        return ((try? contexte.fetch(d)) ?? [])
            .filter { !estRepasResucrage($0) }
            .map { (heure: $0.heure, glucides: $0.totalGlucides) }
    }

    /// Resucrages de la fenêtre, réunis depuis leurs **deux** sources : le
    /// modèle `Resucrage` (section Journal dédiée, chemin principal) et les
    /// repas entièrement badgés `resucrage` (chemin secondaire, sans intention
    /// déclarée → traités en `correctifHypo`, l'usage du badge).
    static func resucrages(
        _ contexte: ModelContext, depuis: Date
    ) -> [(heure: Date, glucides: Int, intention: IntentionResucrage)] {
        let dR = FetchDescriptor<Resucrage>(predicate: #Predicate { $0.date >= depuis })
        let saisis = ((try? contexte.fetch(dR)) ?? []).map {
            (heure: $0.date, glucides: $0.glucidesTotal, intention: $0.intention)
        }
        let dM = FetchDescriptor<Repas>(predicate: #Predicate { $0.heure >= depuis })
        let badges = ((try? contexte.fetch(dM)) ?? [])
            .filter(estRepasResucrage)
            .map {
                (heure: $0.heure, glucides: $0.totalGlucides,
                 intention: IntentionResucrage.correctifHypo)
            }
        return (saisis + badges).sorted { $0.heure < $1.heure }
    }

    /// Un repas non vide dont **tous** les aliments sont badgés resucrage.
    private static func estRepasResucrage(_ repas: Repas) -> Bool {
        !repas.aliments.isEmpty && repas.aliments.allSatisfy(\.resucrage)
    }

    static func sports(
        _ contexte: ModelContext, depuis: Date
    ) -> [(debut: Date, resume: SportResume)] {
        let d = FetchDescriptor<ActiviteSportive>(predicate: #Predicate { $0.dateDebut >= depuis })
        return ((try? contexte.fetch(d)) ?? []).map {
            (debut: $0.dateDebut,
             resume: SportResume(type: $0.type.rawValue, intensite: $0.intensite.rawValue, dureeMinutes: $0.dureeMinutes))
        }
    }

    static func pauses(_ contexte: ModelContext, depuis: Date) -> [(debut: Date, fin: Date?)] {
        // Peu nombreuses : on récupère tout et on filtre les obsolètes en
        // Swift (les bornes `Date?` sont délicates dans un #Predicate).
        let d = FetchDescriptor<PeriodePause>()
        return ((try? contexte.fetch(d)) ?? [])
            .filter { ($0.fin ?? Date()) >= depuis }
            .map { (debut: $0.debut, fin: $0.fin) }
    }
}
