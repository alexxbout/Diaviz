//
//  CalculDoseRatioChangement.swift
//  diaviz
//

import Foundation

// MARK: - Entrée

/// Un repas exploitable pour comparer dose et verdict avant/après un
/// changement de ratio — mappé par `AnalyseRatioService` depuis **tout**
/// l'historique de repas d'une section, contrairement à `EntreeRatioRepas`
/// qui exclut déjà tout ce qui précède le dernier changement (elle a besoin
/// du ratio *configuré actuellement* pour calculer une dose suggérée, donc
/// ne peut pas représenter la période « avant »).
nonisolated struct EntreeDoseChangement: Sendable, Equatable {
    let heure: Date
    /// Dose couvrant les glucides (`totalInsuline - doseCorrection`).
    let doseAppliquee: Double
    let verdict: VerdictGlycemique
}

// MARK: - Résultat

nonisolated struct StatsPeriodeRatio: Sendable, Equatable {
    let doseMoyenne: Double
    let tauxBon: Double
    let effectif: Int
}

/// Comparaison dose/verdict avant vs après le dernier changement de ratio
/// d'une section. `avant` est `nil` quand aucun repas exploitable ne précède
/// la date de changement (première configuration du ratio, ou historique
/// trop court) — la comparaison ne porte alors que sur « après », sans
/// référence à afficher en vis-à-vis.
nonisolated struct ComparaisonChangementRatio: Sendable, Equatable {
    let dateChangement: Date
    let avant: StatsPeriodeRatio?
    let apres: StatsPeriodeRatio
}

// MARK: - Calculateur

/// Compare la dose moyenne et le taux de bons verdicts avant/après le
/// dernier changement de ratio d'une section — même matière première que le
/// mining R1 (`CalculRatioObserve`), lue sous un autre axe (fenêtre
/// temporelle plutôt que tranche d'écart de dose). Le verdict d'un repas est
/// une propriété du repas lui-même (réponse glycémique observée), pas du
/// ratio configuré au moment de l'analyse : comparer deux fenêtres
/// temporelles reste valide même si `EntreeRatioRepas` exclut tout ce qui
/// précède le changement.
nonisolated enum CalculDoseRatioChangement {

    /// Repas minimum après le changement pour qu'une comparaison ait un
    /// sens — même valeur que `CarteAnalyseRatio.repasAvantOubliDuChangement`,
    /// dupliquée intentionnellement (deux usages indépendants d'un même
    /// jugement de recul, pas de dépendance croisée entre une vue et un
    /// calculateur).
    static let effectifMinimalComparaison = 5

    /// `nil` tant que la période « après » n'a pas atteint
    /// `effectifMinimalComparaison` — pas de comparaison à moitié fondée.
    static func comparer(entrees: [EntreeDoseChangement], dateChangement: Date) -> ComparaisonChangementRatio? {
        let apres = entrees.filter { $0.heure >= dateChangement }
        guard let statsApres = stats(apres), statsApres.effectif >= effectifMinimalComparaison else { return nil }
        let avant = entrees.filter { $0.heure < dateChangement }
        return ComparaisonChangementRatio(dateChangement: dateChangement, avant: stats(avant), apres: statsApres)
    }

    private static func stats(_ entrees: [EntreeDoseChangement]) -> StatsPeriodeRatio? {
        guard !entrees.isEmpty else { return nil }
        let doseMoyenne = entrees.reduce(0) { $0 + $1.doseAppliquee } / Double(entrees.count)
        let bons = entrees.filter { $0.verdict == .bon }.count
        return StatsPeriodeRatio(
            doseMoyenne: doseMoyenne, tauxBon: Double(bons) / Double(entrees.count), effectif: entrees.count
        )
    }
}
