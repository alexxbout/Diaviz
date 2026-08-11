//
//  CalculGlucidesHebdo.swift
//  diaviz
//

import Foundation

// MARK: - Résultat

/// Total de glucides d'un jour calendaire — toujours peuplé pour les 14
/// jours de la fenêtre, y compris à 0 quand aucun repas n'a été enregistré :
/// le graphique ne doit pas avoir de trou silencieux.
nonisolated struct PointGlucidesJour: Sendable, Equatable, Hashable, Identifiable {
    let jour: Date
    let totalGlucides: Int
    var id: Date { jour }
}

/// `Hashable` pour servir d'item à `navigationDestination(item:)`
/// (`AccueilVue` → `PageGlucides`), même pattern que `Date` pour
/// `jourDetailScore`.
nonisolated struct SyntheseGlucidesHebdo: Sendable, Equatable, Hashable {
    let moyenneCetteSemaine: Double
    let moyenneSemaineDerniere: Double
    /// 14 jours, du plus ancien (J-13) au plus récent (J0 = aujourd'hui,
    /// partiel).
    let serieJournaliere: [PointGlucidesJour]
}

// MARK: - Calculateur

/// Agrège les glucides consommés par jour calendaire sur les 14 derniers
/// jours et compare la moyenne quotidienne des 7 derniers jours à celle des
/// 7 précédents. Purement descriptif — aucune tranche jugée bonne ou
/// mauvaise, contrairement à `CalculRatioObserve` : manger plus ou moins de
/// glucides n'est ni un succès ni un échec.
nonisolated enum CalculGlucidesHebdo {

    /// Jours avec au moins un repas logué, minimum par fenêtre de 7 jours,
    /// pour que la moyenne ait un sens. Un jour sans repas enregistré n'est
    /// pas compté comme un jour à 0 g — on ne sait pas s'il s'agit d'un
    /// jeûne réel ou d'un simple trou de saisie (« Conscience de la qualité
    /// des données », voir CLAUDE.md) — donc `nil` plutôt qu'une moyenne
    /// gonflée ou écrasée par des trous silencieux.
    static let joursMinimumParSemaine = 3

    static func analyser(
        repas: [Repas], maintenant: Date = Date(), calendrier: Calendar = .current
    ) -> SyntheseGlucidesHebdo? {
        let aujourdhui = calendrier.startOfDay(for: maintenant)
        let jours: [Date] = (0..<14).compactMap { offset in
            calendrier.date(byAdding: .day, value: -(13 - offset), to: aujourdhui)
        }
        guard jours.count == 14 else { return nil }

        // Respecte le mode pause du hub (voyage, maladie…) comme le reste
        // des analyses — un repas exclu ne doit pas peser dans la tendance.
        let exploitables = repas.filter { !$0.exclureDesAnalyses }

        var totauxParJour: [Date: Int] = [:]
        var joursAvecRepas: Set<Date> = []
        for r in exploitables {
            let jour = calendrier.startOfDay(for: r.heure)
            totauxParJour[jour, default: 0] += r.totalGlucides
            joursAvecRepas.insert(jour)
        }

        let serie = jours.map { PointGlucidesJour(jour: $0, totalGlucides: totauxParJour[$0] ?? 0) }

        guard
            let moyenneDerniere = moyenne(jours: Array(jours.prefix(7)), totaux: totauxParJour, joursAvecRepas: joursAvecRepas),
            let moyenneActuelle = moyenne(jours: Array(jours.suffix(7)), totaux: totauxParJour, joursAvecRepas: joursAvecRepas)
        else { return nil }

        return SyntheseGlucidesHebdo(
            moyenneCetteSemaine: moyenneActuelle, moyenneSemaineDerniere: moyenneDerniere, serieJournaliere: serie
        )
    }

    private static func moyenne(jours: [Date], totaux: [Date: Int], joursAvecRepas: Set<Date>) -> Double? {
        let actifs = jours.filter { joursAvecRepas.contains($0) }
        guard actifs.count >= joursMinimumParSemaine else { return nil }
        let somme = actifs.reduce(0) { $0 + (totaux[$1] ?? 0) }
        return Double(somme) / Double(actifs.count)
    }
}
