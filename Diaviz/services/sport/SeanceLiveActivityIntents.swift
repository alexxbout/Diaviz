//
//  SeanceLiveActivityIntents.swift
//  diaviz
//
//  ⚠️ Fichier PARTAGÉ app ↔ widget (Target Membership sur les deux cibles) :
//  le type des intents doit compiler côté widget (pour `Button(intent:)`),
//  et leur `perform()` s'exécute dans le process de l'app. La logique passe
//  par `ControleurSeanceLive` (sans SwiftData) pour rester compilable des
//  deux côtés.
//

import AppIntents

/// Bouton Pause/Reprendre de la Dynamic Island / écran verrouillé.
struct BasculerPauseSeanceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause ou reprise de la séance"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await ControleurSeanceLive.basculerPause()
        return .result()
    }
}

/// Bouton Terminer de la Dynamic Island / écran verrouillé. Fige la séance
/// pour l'enregistrement, clôt la Live Activity et ouvre l'app.
struct TerminerSeanceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Terminer la séance"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await ControleurSeanceLive.terminer()
        return .result()
    }
}
