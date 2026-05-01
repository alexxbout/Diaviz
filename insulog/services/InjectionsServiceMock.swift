//
//  InjectionsServiceMock.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation
import Observation

/// Service mocké pour la page Médications.
///
/// Expose un jeu d'injections cohérent sur 7 jours :
/// - 1 insuline lente prise hier soir à 22:00 (Lantus, cuisse gauche)
/// - 2 corrections rapides du jour (09:15 et 14:30)
/// - 3 bolus repas du jour (petit-déjeuner, déjeuner, dîner)
/// - quelques injections sur les 6 jours précédents pour permettre
///   la navigation dans le graphe
///
/// L'instance est partagée via `.shared` — la page Médications
/// l'observe via `@State` pour profiter du nouveau pattern
/// `@Observable` (Observation framework iOS 17+).
///
/// Branchera l'API NestJS / Prisma plus tard ; l'API publique
/// (`injections`, `heureHabituelleLente`) reste stable.
@Observable
@MainActor
final class InjectionsServiceMock {

    static let shared = InjectionsServiceMock()

    /// Toutes les injections connues, multi-jours, non triées.
    private(set) var injections: [Injection]

    /// Heure habituelle de la lente, configurable depuis les réglages.
    /// Mockée à 22:00 pour cette implémentation.
    let heureHabituelleLente: HeureDuJour = HeureDuJour(heure: 22, minute: 0)

    private init() {
        self.injections = Self.donneesInitiales()
    }

    // MARK: - Lecture par jour

    /// Injections d'un jour donné, triées par heure ascendante.
    func injectionsDuJour(_ jour: Date) -> [Injection] {
        let cal = Calendar.current
        return injections
            .filter { cal.isDate($0.heure, inSameDayAs: jour) }
            .sorted { $0.heure < $1.heure }
    }

    /// Lente du jour donné, s'il y en a une enregistrée.
    func lenteDuJour(_ jour: Date) -> Injection? {
        injectionsDuJour(jour).first { $0.type == .lente }
    }

    // MARK: - Écriture (mock — uniquement local, pas de persistance)

    func ajouter(_ injection: Injection) {
        injections.append(injection)
    }

    // MARK: - Données mockées

    private static func donneesInitiales() -> [Injection] {
        let cal = Calendar.current

        func dateA(_ h: Int, _ m: Int = 0, ilYA jours: Int = 0) -> Date {
            let jourBase = cal.date(byAdding: .day, value: -jours, to: Date()) ?? Date()
            return cal.date(bySettingHour: h, minute: m, second: 0, of: jourBase) ?? Date()
        }

        return [
            // MARK: Aujourd'hui — 2 corrections + 3 bolus repas
            Injection(
                type: .rapideCorrection,
                dose: 0.5,
                heure: dateA(9, 15),
                zoneInjection: .ventre,
                coteInjection: .gauche,
                note: nil,
                glycemieAuMoment: 240
            ),
            Injection(
                type: .rapideCorrection,
                dose: 1.5,
                heure: dateA(14, 30),
                zoneInjection: .bras,
                coteInjection: .droite,
                note: nil,
                glycemieAuMoment: 165
            ),
            Injection(
                type: .rapideRepas,
                dose: 4.0,
                heure: dateA(8, 30),
                zoneInjection: .ventre,
                coteInjection: .droite,
                repasAssocieId: UUID(),
                nomMedicament: "NovoRapid",
                labelRepas: "Petit-déjeuner",
                emojiRepas: "🍞"
            ),
            Injection(
                type: .rapideRepas,
                dose: 6.5,
                heure: dateA(13, 0),
                zoneInjection: .ventre,
                coteInjection: .gauche,
                repasAssocieId: UUID(),
                nomMedicament: "NovoRapid",
                labelRepas: "Déjeuner",
                emojiRepas: "🍝"
            ),
            Injection(
                type: .rapideRepas,
                dose: 5.0,
                heure: dateA(19, 30),
                zoneInjection: .cuisse,
                coteInjection: .droite,
                repasAssocieId: UUID(),
                nomMedicament: "NovoRapid",
                labelRepas: "Dîner",
                emojiRepas: "🍚"
            ),

            // MARK: Hier — lente + 2 bolus repas + 1 correction
            Injection(
                type: .lente,
                dose: 12,
                heure: dateA(22, 0, ilYA: 1),
                zoneInjection: .cuisse,
                coteInjection: .gauche,
                nomMedicament: "Lantus"
            ),
            Injection(
                type: .rapideRepas,
                dose: 5.0,
                heure: dateA(8, 0, ilYA: 1),
                zoneInjection: .ventre,
                coteInjection: .gauche,
                labelRepas: "Petit-déjeuner",
                emojiRepas: "🥐"
            ),
            Injection(
                type: .rapideRepas,
                dose: 7.0,
                heure: dateA(12, 45, ilYA: 1),
                zoneInjection: .ventre,
                coteInjection: .droite,
                labelRepas: "Déjeuner",
                emojiRepas: "🍕"
            ),
            Injection(
                type: .rapideCorrection,
                dose: 1.0,
                heure: dateA(16, 0, ilYA: 1),
                zoneInjection: .bras,
                coteInjection: .gauche,
                glycemieAuMoment: 200
            ),

            // MARK: J-2 — lente + 3 repas
            Injection(
                type: .lente,
                dose: 12,
                heure: dateA(22, 5, ilYA: 2),
                zoneInjection: .cuisse,
                coteInjection: .droite,
                nomMedicament: "Lantus"
            ),
            Injection(
                type: .rapideRepas,
                dose: 4.5,
                heure: dateA(7, 45, ilYA: 2),
                zoneInjection: .ventre,
                coteInjection: .gauche,
                labelRepas: "Petit-déjeuner",
                emojiRepas: "🥣"
            ),
            Injection(
                type: .rapideRepas,
                dose: 5.5,
                heure: dateA(13, 15, ilYA: 2),
                zoneInjection: .ventre,
                coteInjection: .centre,
                labelRepas: "Déjeuner",
                emojiRepas: "🥗"
            ),
            Injection(
                type: .rapideRepas,
                dose: 6.0,
                heure: dateA(20, 0, ilYA: 2),
                zoneInjection: .cuisse,
                coteInjection: .gauche,
                labelRepas: "Dîner",
                emojiRepas: "🍜"
            ),

            // MARK: J-3 — lente + 2 repas + 2 corrections
            Injection(
                type: .lente,
                dose: 17.5,
                heure: dateA(22, 0, ilYA: 3),
                zoneInjection: .cuisse,
                coteInjection: .gauche,
                nomMedicament: "Lantus"
            ),
            Injection(
                type: .rapideRepas,
                dose: 3.5,
                heure: dateA(8, 30, ilYA: 3),
                zoneInjection: .ventre,
                coteInjection: .droite,
                labelRepas: "Petit-déjeuner",
                emojiRepas: "🍞"
            ),
            Injection(
                type: .rapideRepas,
                dose: 6.0,
                heure: dateA(12, 30, ilYA: 3),
                zoneInjection: .bras,
                coteInjection: .droite,
                labelRepas: "Déjeuner",
                emojiRepas: "🍔"
            ),
            Injection(
                type: .rapideCorrection,
                dose: 0.5,
                heure: dateA(11, 0, ilYA: 3),
                zoneInjection: .ventre,
                coteInjection: .gauche,
                glycemieAuMoment: 195
            ),
            Injection(
                type: .rapideCorrection,
                dose: 2.0,
                heure: dateA(17, 30, ilYA: 3),
                zoneInjection: .cuisse,
                coteInjection: .droite,
                glycemieAuMoment: 270
            ),

            // MARK: J-4 — lente + 2 repas (journée légère)
            Injection(
                type: .lente,
                dose: 12,
                heure: dateA(21, 50, ilYA: 4),
                zoneInjection: .fesse,
                coteInjection: .droite,
                nomMedicament: "Lantus"
            ),
            Injection(
                type: .rapideRepas,
                dose: 5.0,
                heure: dateA(13, 0, ilYA: 4),
                zoneInjection: .ventre,
                coteInjection: .gauche,
                labelRepas: "Déjeuner",
                emojiRepas: "🥪"
            ),
            Injection(
                type: .rapideRepas,
                dose: 4.5,
                heure: dateA(20, 0, ilYA: 4),
                zoneInjection: .ventre,
                coteInjection: .droite,
                labelRepas: "Dîner",
                emojiRepas: "🐟"
            ),

            // MARK: J-5 — lente + 3 repas
            Injection(
                type: .lente,
                dose: 12,
                heure: dateA(22, 10, ilYA: 5),
                zoneInjection: .cuisse,
                coteInjection: .gauche,
                nomMedicament: "Lantus"
            ),
            Injection(
                type: .rapideRepas,
                dose: 4.0,
                heure: dateA(8, 15, ilYA: 5),
                zoneInjection: .ventre,
                coteInjection: .droite,
                labelRepas: "Petit-déjeuner",
                emojiRepas: "🥯"
            ),
            Injection(
                type: .rapideRepas,
                dose: 5.5,
                heure: dateA(12, 30, ilYA: 5),
                zoneInjection: .bras,
                coteInjection: .gauche,
                labelRepas: "Déjeuner",
                emojiRepas: "🥗"
            ),
            Injection(
                type: .rapideRepas,
                dose: 6.5,
                heure: dateA(20, 30, ilYA: 5),
                zoneInjection: .cuisse,
                coteInjection: .droite,
                labelRepas: "Dîner",
                emojiRepas: "🍝"
            ),

            // MARK: J-6 — lente seulement
            Injection(
                type: .lente,
                dose: 12,
                heure: dateA(22, 0, ilYA: 6),
                zoneInjection: .cuisse,
                coteInjection: .droite,
                nomMedicament: "Lantus"
            ),
            Injection(
                type: .rapideRepas,
                dose: 5.0,
                heure: dateA(13, 30, ilYA: 6),
                zoneInjection: .ventre,
                coteInjection: .centre,
                labelRepas: "Déjeuner",
                emojiRepas: "🍱"
            ),
        ]
    }
}

/// Heure du jour mémorisée comme couple (heure, minute), indépendante
/// de la date. Sert au paramétrage de l'heure habituelle de la lente.
struct HeureDuJour: Sendable, Equatable {
    let heure: Int
    let minute: Int

    /// Projette `(heure, minute)` sur la journée `jour` (par défaut
    /// aujourd'hui), pour comparaison avec `Date.now`.
    func date(pour jour: Date = Date()) -> Date {
        Calendar.current.date(
            bySettingHour: heure,
            minute: minute,
            second: 0,
            of: jour
        ) ?? jour
    }

    /// Format affichage 24h (« 22:00 »).
    var libelle: String {
        String(format: "%02d:%02d", heure, minute)
    }
}
