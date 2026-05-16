//
//  EtatRappelLente.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation

/// État d'affichage de la carte contextuelle « Insuline lente » de
/// l'accueil. Décrit la **gradation visuelle** du rappel selon le retard
/// pris par rapport à l'heure habituelle configurée par l'utilisateur.
///
/// La carte est **purement informative** — elle ne prescrit jamais de
/// dose et ne presse pas l'utilisateur. Les trois paliers (doux →
/// urgent → alerte) servent uniquement à augmenter la visibilité au fur
/// et à mesure que le retard se prolonge, sans jamais formuler de
/// directive médicale.
///
/// Le calcul de l'état (et la décision de masquer la carte) vit dans
/// `calculer(now:contexte:)` — l'enum reste un type-données pur, sans
/// dépendance à `Date.now`, pour rester testable et déterministe.
enum EtatRappelLente: Equatable, Sendable {

    /// Fenêtre douce : de `heureHabituelle - 1h` à `heureHabituelle + 30min`.
    /// Couleur d'accent bleue, fond neutre — simple rappel visuel.
    case doux

    /// Fenêtre urgente : de `heureHabituelle + 30min` à `heureHabituelle + 2h`.
    /// Couleur d'accent orange, fond légèrement teinté.
    case urgent

    /// Fenêtre d'alerte : au-delà de `heureHabituelle + 2h`.
    /// Couleur d'accent rouge, fond légèrement teinté.
    case alerte
}

// MARK: - Calcul depuis un contexte

extension EtatRappelLente {

    /// Détermine l'état d'affichage à partir de l'heure courante et du
    /// contexte utilisateur. Retourne `nil` **quand la carte doit être
    /// masquée** :
    /// - la lente a déjà été prise aujourd'hui, OU
    /// - on est encore à plus d'une heure avant l'heure habituelle
    ///   (trop tôt pour rappeler quoi que ce soit).
    ///
    /// `now` est paramétrable pour faciliter les tests et previews ;
    /// par défaut on consulte l'horloge système.
    static func calculer(
        now: Date = .now,
        contexte: ContexteLente
    ) -> EtatRappelLente? {

        // La lente a été prise aujourd'hui → plus rien à rappeler.
        guard !contexte.priseAujourdhui else { return nil }

        // `diff` est positif quand l'heure habituelle est dépassée,
        // négatif quand elle est encore à venir dans la journée.
        let diff = now.timeIntervalSince(contexte.heureHabituelle)

        let trenteMinutes: TimeInterval = 30 * 60
        let uneHeure: TimeInterval = 60 * 60
        let deuxHeures: TimeInterval = 2 * 60 * 60

        // Trop tôt : la fenêtre d'affichage commence à -1h.
        if diff < -uneHeure { return nil }

        // -1h ≤ diff ≤ +30min → rappel doux
        if diff <= trenteMinutes { return .doux }

        // +30min < diff ≤ +2h → rappel urgent
        if diff <= deuxHeures { return .urgent }

        // diff > +2h → alerte
        return .alerte
    }
}
