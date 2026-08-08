//
//  MetriquesAccueilService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

// MARK: - Modèles (déplacés depuis l'ancien AccueilMetriquesServiceMock)

/// Lecture CGM unique — utilisée par la mini-courbe 24h de la carte Hypos.
struct LectureCgm: Sendable, Equatable {
    let heure: Date
    let valeur: Double
}

/// Catégorie d'insuline affichée sur le badge de la carte « Injection » de
/// l'accueil — vue simplifiée à deux paliers (rapide vs lente).
enum CategorieInjectionAccueil: String, Sendable, Equatable {
    case rapide = "Rapide"
    case lente = "Lente"
}

/// Snapshot des 4 cartes de la grille d'accueil. L'IOB est branché séparément
/// (`IOBService`) — `pointsIOB` n'est plus alimenté par ce service (gardé pour
/// les previews qui exercent la carte IOB).
struct MetriquesAccueil: Sendable, Equatable {
    let hyposAujourdhui: Int
    let hyposSeveres: Int
    let hyposLegeres: Int
    /// `nil` quand le hub ne contient aucune injection — distinct d'une
    /// injection de 0 unité posée à l'instant (voir `CarteDerniereInjection`).
    let derniereInjection: (dose: Double, depuis: TimeInterval, type: CategorieInjectionAccueil)?
    /// `nil` quand le hub ne contient aucun repas — même logique.
    let dernierRepas: (glucides: Double, depuis: TimeInterval, emojis: [String])?
    let pointsCgmJournee: [LectureCgm]
    let pointsIOB: [PointIOB]

    /// IOB instantané — dérivé de `pointsIOB.first` (previews uniquement).
    var iob: Double { pointsIOB.first?.iob ?? 0 }

    static func == (lhs: MetriquesAccueil, rhs: MetriquesAccueil) -> Bool {
        lhs.hyposAujourdhui == rhs.hyposAujourdhui
            && lhs.hyposSeveres == rhs.hyposSeveres
            && lhs.hyposLegeres == rhs.hyposLegeres
            && lhs.derniereInjection?.dose == rhs.derniereInjection?.dose
            && lhs.derniereInjection?.depuis == rhs.derniereInjection?.depuis
            && lhs.derniereInjection?.type == rhs.derniereInjection?.type
            && lhs.dernierRepas?.glucides == rhs.dernierRepas?.glucides
            && lhs.dernierRepas?.depuis == rhs.dernierRepas?.depuis
            && lhs.dernierRepas?.emojis == rhs.dernierRepas?.emojis
            && lhs.pointsCgmJournee == rhs.pointsCgmJournee
            && lhs.pointsIOB == rhs.pointsIOB
    }

    /// État neutre avant le premier chargement / hub vide.
    static let vide = MetriquesAccueil(
        hyposAujourdhui: 0, hyposSeveres: 0, hyposLegeres: 0,
        derniereInjection: nil, dernierRepas: nil,
        pointsCgmJournee: [], pointsIOB: []
    )
}

// MARK: - Service

/// Service **réel** des métriques d'accueil — assemble les 3 cartes (hypos du
/// jour, dernière injection, dernier repas) depuis le hub. La carte IOB est
/// alimentée séparément par `IOBService`.
///
/// « Un hub, des dérivations » : rien de persisté, recalculé à `recharger()`
/// (à chaque apparition de l'accueil, comme le score et l'IOB).
@Observable
@MainActor
final class MetriquesAccueilService {

    private var contexte: ModelContext?
    private(set) var metriques: MetriquesAccueil = .vide

    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    func recharger() {
        guard let contexte else { return }
        let now = Date()
        let debutJour = ScoreService.debutJourMetabolique(pour: now)

        // CGM du jour métabolique → hypos (épisodes) + mini-courbe.
        let cgmDescr = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= debutJour },
            sortBy: [SortDescriptor(\.date)]
        )
        let cgm = (try? contexte.fetch(cgmDescr)) ?? []
        let (hypo, severe) = CalculScoreJournalier.comptageHypos(cgm.map(\.valeur))

        // Dernière injection (toutes catégories).
        var injDescr = FetchDescriptor<Injection>(sortBy: [SortDescriptor(\.heure, order: .reverse)])
        injDescr.fetchLimit = 1
        let inj = (try? contexte.fetch(injDescr))?.first

        // Dernier repas non vide.
        var repasDescr = FetchDescriptor<Repas>(sortBy: [SortDescriptor(\.heure, order: .reverse)])
        repasDescr.fetchLimit = 1
        let repas = (try? contexte.fetch(repasDescr))?.first

        metriques = MetriquesAccueil(
            hyposAujourdhui: hypo,
            hyposSeveres: severe,
            hyposLegeres: max(0, hypo - severe),
            derniereInjection: inj.map {
                (dose: $0.dose, depuis: now.timeIntervalSince($0.heure), type: $0.type == .lente ? .lente : .rapide)
            },
            dernierRepas: repas.map {
                (glucides: Double($0.totalGlucides), depuis: now.timeIntervalSince($0.heure), emojis: $0.aliments.map(\.emoji))
            },
            pointsCgmJournee: cgm.map { LectureCgm(heure: $0.date, valeur: Double($0.valeur)) },
            pointsIOB: []
        )
    }
}

#if DEBUG
// MARK: - Fabriques de preview

extension MetriquesAccueil {

    /// Journée typique sans incident — 0 hypo, IOB modéré, repas récent.
    static let mockNormal: MetriquesAccueil = {
        let now = Date()
        let injections = [
            InjectionPourIOB(heure: now.addingTimeInterval(-2 * 3600), dose: 4.0),
            InjectionPourIOB(heure: now.addingTimeInterval(-45 * 60), dose: 1.5),
        ]
        return MetriquesAccueil(
            hyposAujourdhui: 0, hyposSeveres: 0, hyposLegeres: 0,
            derniereInjection: (dose: 4.0, depuis: 60 * 60 * 2 + 13 * 60, type: .rapide),
            dernierRepas: (glucides: 45, depuis: 60 * 60 * 2 + 18 * 60, emojis: ["🍞", "🧀", "🥛"]),
            pointsCgmJournee: cgmJourneeApercu(avecHypos: false),
            pointsIOB: IOBCalculateur.courbe(injections: injections, depuis: now, diaHeures: 4, picMinutes: 75)
        )
    }()

    /// Journée à risque — 2 hypos (1 sévère), IOB encore élevé.
    static let mockAlerte: MetriquesAccueil = {
        let now = Date()
        let injections = [
            InjectionPourIOB(heure: now.addingTimeInterval(-90 * 60), dose: 4.0),
            InjectionPourIOB(heure: now.addingTimeInterval(-30 * 60), dose: 2.0),
        ]
        return MetriquesAccueil(
            hyposAujourdhui: 2, hyposSeveres: 1, hyposLegeres: 1,
            derniereInjection: (dose: 6.5, depuis: 60 * 60 + 5 * 60, type: .rapide),
            dernierRepas: (glucides: 72, depuis: 60 * 60 + 8 * 60, emojis: ["🍝", "🧀", "🥖"]),
            pointsCgmJournee: cgmJourneeApercu(avecHypos: true),
            pointsIOB: IOBCalculateur.courbe(injections: injections, depuis: now, diaHeures: 4, picMinutes: 75)
        )
    }()

    /// Journée calme — 0 hypo, IOB résiduel quasi nul, dernière injection lente.
    static let mockCalme: MetriquesAccueil = {
        let now = Date()
        let injections = [InjectionPourIOB(heure: now.addingTimeInterval(-3.5 * 3600), dose: 3.5)]
        return MetriquesAccueil(
            hyposAujourdhui: 0, hyposSeveres: 0, hyposLegeres: 0,
            derniereInjection: (dose: 12, depuis: 60 * 60 * 8, type: .lente),
            dernierRepas: (glucides: 28, depuis: 60 * 60 * 6, emojis: ["🥗", "🥑"]),
            pointsCgmJournee: cgmJourneeApercu(avecHypos: false),
            pointsIOB: IOBCalculateur.courbe(injections: injections, depuis: now, diaHeures: 4, picMinutes: 75)
        )
    }()

    /// Journée neuve — aucune donnée saisie. Vérifie que « Injection » et
    /// « Repas » affichent leur état vide plutôt qu'une fausse valeur à 0.
    static let mockVide: MetriquesAccueil = MetriquesAccueil(
        hyposAujourdhui: 0, hyposSeveres: 0, hyposLegeres: 0,
        derniereInjection: nil, dernierRepas: nil,
        pointsCgmJournee: cgmJourneeApercu(avecHypos: false), pointsIOB: []
    )
}

/// Génère une journée CGM synthétique (48 points / 30 min) pour les previews.
private func cgmJourneeApercu(avecHypos: Bool) -> [LectureCgm] {
    let cal = Calendar.current
    let debutJour = cal.startOfDay(for: Date())
    return (0..<48).map { i in
        let minutes = i * 30
        let heure = cal.date(byAdding: .minute, value: minutes, to: debutJour) ?? debutJour
        let h = Double(minutes) / 60.0
        var valeur = 125.0 + 25 * sin((h - 6) * .pi / 12) + 12 * sin(h * .pi / 3)
        if avecHypos {
            valeur -= 95 * exp(-pow(abs(h - 9.25) * 1.6, 2))
            valeur -= 90 * exp(-pow(abs(h - 14.5) * 1.6, 2))
        }
        return LectureCgm(heure: heure, valeur: max(40, min(280, valeur)))
    }
}
#endif
