//
//  EtatAnalyse.swift
//  diaviz
//
//  Created by Alexandre on 30/04/2026.
//

import Foundation

// MARK: - EtatAnalyse
//
// État du pré-calcul de la réponse glycémique pour un repas donné.
// La row du Journal s'adapte selon le cas — on n'affiche jamais une
// courbe partielle ou trompeuse, on signale plutôt l'état réel.
nonisolated enum EtatAnalyse: Sendable {
    /// L'analyse est terminée et la courbe est exploitable.
    case disponible(ReponseGlycemique)
    /// Le repas est trop récent (< 3h) : on attend que la fenêtre T+4h se remplisse.
    case enAttente(minutesRestantes: Int)
    /// CGM absent ou couverture < 80 % sur la fenêtre — pas d'analyse fiable possible.
    case donneesManquantes
    /// Repas sans dose d'insuline : la réponse glycémique n'a pas de sens à analyser.
    case sansInjection
}
