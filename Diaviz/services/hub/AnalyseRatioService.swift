//
//  AnalyseRatioService.swift
//  diaviz
//

import Foundation
import Observation

/// Service **réel** du mining du ratio observé (cœur ML de R1) — cache en
/// mémoire, recalculé sur mutation du hub plutôt qu'à chaque frappe de
/// saisie. Lit directement `RepasService.repas` (déjà chargé et annoté, pas
/// de fetch SwiftData séparé) et délègue à `CalculRatioObserve` (pur).
///
/// Pattern de démarrage aligné sur `AnalyseBasaleService` : `analyse` prêt à
/// l'affichage dès l'init (état « données insuffisantes »), recalculé via
/// `recalculer(depuis:)` après chaque mutation connue du hub.
@Observable
@MainActor
final class AnalyseRatioService {

    private(set) var analyse: AnalyseRatioObserve = .vide

    /// Recalcule depuis les repas déjà chargés/annotés par `RepasService` —
    /// aucun fetch CGM ni régression ici, juste un mapping en value types et
    /// un comptage : volume trivial (quelques milliers de repas au grand
    /// maximum), pas besoin de `Task.detached`.
    func recalculer(depuis repas: [Repas]) {
        let profil = ProfilService.shared.profil
        let (entrees, totalRepasAnalyses) = mapperEntrees(repas, profil: profil)
        analyse = CalculRatioObserve.analyser(entrees: entrees, totalRepasAnalyses: totalRepasAnalyses)
    }

    /// Explose chaque repas exploitable en une ou plusieurs `EntreeRatioRepas`
    /// (une par raison d'ajustement présente, ou une seule pour le groupe
    /// moment si aucun ajustement) — voir `GroupeRatio`. Le second élément du
    /// tuple compte les **repas distincts**, pas les entrées, pour que le
    /// seuil global (`donneesMinimales`) ne soit pas gonflé par un repas à
    /// plusieurs ajustements.
    private func mapperEntrees(
        _ repas: [Repas], profil: ProfilUtilisateur
    ) -> (entrees: [EntreeRatioRepas], totalRepasAnalyses: Int) {
        var entrees: [EntreeRatioRepas] = []
        var totalRepasAnalyses = 0

        for r in repas {
            // Exclusion explicite (toggle « Exclure des analyses ») ou
            // événement contextuel non structuré : hors mining, quel que
            // soit le groupe (ni ratio de base, ni ajustement).
            guard !r.exclureDesAnalyses, r.contexteLibre == nil else { continue }
            guard let verdict = r.verdictPersiste, verdict != .indetermine,
                  r.totalGlucides > 0 else { continue }
            let doseCouvrante = r.totalInsuline - (r.doseCorrection ?? 0)
            guard doseCouvrante > 0 else { continue }

            let sectionReelle = SectionRepas(heure: r.heure, horaires: profil.horairesRepas)
            guard let ratioConfigure = InsightsService.ratioConfigure(section: sectionReelle, profil: profil),
                  ratioConfigure > 0 else { continue }

            let doseSuggeree = Double(r.totalGlucides) / ratioConfigure
            func entree(_ groupe: GroupeRatio) -> EntreeRatioRepas {
                EntreeRatioRepas(
                    groupe: groupe, doseAppliquee: doseCouvrante, doseSuggeree: doseSuggeree,
                    glucides: r.totalGlucides, verdict: verdict
                )
            }

            if r.ajustements.isEmpty {
                let section = profil.modeRatio == .unique ? nil : sectionReelle
                entrees.append(entree(.moment(section)))
            } else {
                // Un repas ajusté n'alimente jamais le groupe moment (ratio de
                // base) — une entrée par raison distincte présente.
                let raisons = Set(r.ajustements.map(\.raison))
                for raison in raisons { entrees.append(entree(.ajustement(raison))) }
            }
            totalRepasAnalyses += 1
        }

        return (entrees, totalRepasAnalyses)
    }
}
