//
//  RepasGraph.swift
//  diaviz
//
//  Created by Alexandre on 30/04/2026.
//

import SwiftUI

enum VerdictGlycemique: Hashable, Codable, Sendable {
    case bon          // pic resté < 180 mg/dL
    case moyen        // pic entre 180-240 mg/dL
    case mauvais      // pic > 240 mg/dL ou hypo détectée
    case indetermine  // données pas encore disponibles

    var couleur: Color {
        switch self {
        case .bon: .green
        case .moyen: .orange
        case .mauvais: .red
        case .indetermine: .gray
        }
    }

    var libelle: String {
        switch self {
        case .bon: "Pic resté en cible"
        case .moyen: "Pic modéré"
        case .mauvais: "Pic élevé"
        case .indetermine: "En attente d'analyse"
        }
    }
}

/// Pourquoi un repas a reçu le verdict `.mauvais` — une hypoglycémie et un
/// pic élevé sont deux événements opposés, les confondre sous une seule
/// couleur rouge masquait l'information la plus utile.
///
/// Volontairement **séparée** de `VerdictGlycemique` plutôt qu'ajoutée comme
/// un quatrième cas : l'enum du verdict est persisté (`Repas.verdictPersiste`,
/// export JSON d'`ArchiveDonneesService`) et lu par une quinzaine de fichiers.
/// Un champ à part se greffe sans migration ni recompilation en cascade.
enum RaisonMauvaisVerdict: String, Hashable, Codable, Sendable {
    /// Glycémie descendue sous le seuil d'hypoglycémie du profil.
    case hypoglycemie
    /// Pic élevé, ou excursion jamais redescendue en cible.
    case hyperglycemie

    /// Rouge réservé à l'hypoglycémie — convention des lecteurs CGM (Dexcom,
    /// Libre) où le rouge signale toujours le bas. Le pic élevé prend un brun
    /// qui prolonge l'axe « trop haut » déjà porté par l'orange du verdict
    /// `.moyen` : orange = pic modéré, brun = pic élevé.
    var couleur: Color {
        switch self {
        case .hypoglycemie: .red
        case .hyperglycemie: .brown
        }
    }

    var libelle: String {
        switch self {
        case .hypoglycemie: "Hypoglycémie"
        case .hyperglycemie: "Pic élevé"
        }
    }

    /// Précision affichée en légende — « hypoglycémie » seul ne dit ni le
    /// seuil ni la fenêtre, alors que les deux sont paramétrables ou peu
    /// évidents.
    func precision(seuils: SeuilsGlycemiques) -> String {
        switch self {
        case .hypoglycemie:
            return "sous \(Int(seuils.hypoglycemie)) mg/dL dans les 4 h"
        case .hyperglycemie:
            return "pic ≥ 250, ou jamais redescendu sous \(Int(seuils.hyperglycemie))"
        }
    }
}

struct RepasGraph: Identifiable, Hashable {
    let id: UUID
    let heure: Date
    let glucides: Double
    let aInjection: Bool
    let verdict: VerdictGlycemique
    let label: String
    let emoji: String

    init(
        id: UUID = UUID(),
        heure: Date,
        glucides: Double,
        aInjection: Bool,
        verdict: VerdictGlycemique,
        label: String,
        emoji: String
    ) {
        self.id = id
        self.heure = heure
        self.glucides = glucides
        self.aInjection = aInjection
        self.verdict = verdict
        self.label = label
        self.emoji = emoji
    }
}

extension RepasGraph {
    /// Convertit un `Repas` métier en projection pour le graphe. Le verdict
    /// provient de la réponse glycémique dérivée du CGM (`Repas.etatAnalyse`,
    /// posée par `RepasService`) — `.indetermine` tant qu'elle n'est pas
    /// disponible (repas récent, sans bolus, ou CGM manquant).
    init(_ repas: Repas, label: String) {
        self.init(
            id: repas.id,
            heure: repas.heure,
            glucides: Double(repas.totalGlucides),
            // `repas.aUneInjection` (pas un recalcul local) : en mode dose
            // globale, `enregistrerDepuisSaisie` remet `insuline = 0` sur
            // chaque aliment (la dose vit sur `doseGlobale`) — un check
            // `aliments.contains { $0.insuline > 0 }` ratait alors tous les
            // repas saisis en dose globale, quelle que soit la dose réelle.
            aInjection: repas.aUneInjection,
            verdict: Self.verdictDepuisEtat(pour: repas),
            label: label,
            emoji: repas.aliments.first?.emojiAffiche ?? "🍽️"
        )
    }

    /// Mappe l'`EtatAnalyse` du repas vers le verdict affiché : seule une
    /// analyse `disponible` porte un verdict coloré, les autres états
    /// (attente, données manquantes, sans injection, non calculé) restent
    /// `.indetermine`.
    private static func verdictDepuisEtat(pour repas: Repas) -> VerdictGlycemique {
        if case .disponible(let reponse) = repas.etatAnalyse {
            return reponse.verdict
        }
        return .indetermine
    }
}
