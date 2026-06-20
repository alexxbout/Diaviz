//
//  AccueilMetriquesServiceMock.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import Foundation
import Observation

// MARK: - Sous-modèles courbes

/// Lecture CGM unique — utilisée par la mini-courbe 24h de la carte
/// Hypos. Le champ `heure` sert d'identifiant naturel dans les
/// `ForEach` (les horodatages sont uniques par construction).
struct LectureCgm: Sendable, Equatable {
    /// Horodatage de la lecture.
    let heure: Date
    /// Glycémie en mg/dL.
    let valeur: Double
}

// `InjectionPourIOB` vit désormais dans l'assembleur `IOBCalculateur`
// (services/derivation) — réutilisé ici pour les courbes de preview.

// `PointIOB` vit désormais dans l'assembleur `IOBCalculateur`.

/// Catégorie d'insuline affichée sur le badge de la carte
/// « Injection » de la page d'accueil. Vue simplifiée à deux
/// paliers — rapide (bolus repas ou correction) vs. lente (basale
/// longue action) — distincte du modèle complet `TypeInjection`
/// du module Médications qui distingue rapide repas / correction.
///
/// `rawValue` est directement le libellé affiché sur le badge.
enum CategorieInjectionAccueil: String, Sendable, Equatable {
    case rapide = "Rapide"
    case lente = "Lente"
}

// MARK: - Modèle

/// Snapshot des métriques affichées sur la grille d'accueil — quatre
/// cartes qui donnent un aperçu instantané de l'état courant : hypos
/// du jour, IOB, dernière injection, dernier repas.
///
/// Toutes les valeurs sont des photos prises à l'instant `t` : c'est à
/// la couche d'analyses (future API NestJS + couche ML) de produire ces
/// chiffres. Le mock se contente d'en jouer plusieurs configurations
/// pour exercer les états visuels (normal / alerte / calme).
struct MetriquesAccueil: Sendable, Equatable {

    /// Nombre total d'hypoglycémies sur la journée courante.
    let hyposAujourdhui: Int

    /// Sous-décompte : hypos sévères (< 54 mg/dL). `hyposSeveres +
    /// hyposLegeres == hyposAujourdhui` est une invariante respectée
    /// par les mocks.
    let hyposSeveres: Int

    /// Sous-décompte : hypos légères (54–69 mg/dL).
    let hyposLegeres: Int

    /// Dose en unités de la dernière injection — rapide (bolus) ou
    /// lente (basale). Le `derniereInjectionType` indique laquelle.
    let derniereInjectionDose: Double

    /// Temps écoulé depuis la dernière injection, en secondes. La carte
    /// la formate dynamiquement (« il y a 2h13 »).
    let derniereInjectionDepuis: TimeInterval

    /// Catégorie de la dernière injection — pilote le badge affiché
    /// sur la carte (orange pour rapide, bleu pour lente).
    let derniereInjectionType: CategorieInjectionAccueil

    /// Glucides du dernier repas, en grammes.
    let dernierRepasGlucides: Double

    /// Temps écoulé depuis le dernier repas, en secondes. La carte
    /// le formate dynamiquement (« il y a 1h30 »).
    let dernierRepasDepuis: TimeInterval

    /// Emojis des aliments du dernier repas. La carte les fait défiler
    /// cycliquement à droite de la valeur. Liste vide → pas d'emoji
    /// affiché.
    let dernierRepasEmojis: [String]

    /// 48 points CGM espacés de 30min sur la journée courante (00h00
    /// → 23h30 local). Consommé par la mini-courbe de `CarteHypos`.
    let pointsCgmJournee: [LectureCgm]

    /// Courbe d'IOB total projetée sur les 6h à venir (échantillonnée
    /// toutes les 15min), précalculée à la construction du snapshot
    /// pour éviter tout recalcul à chaque render. Consommée par la
    /// mini-courbe de `CarteIOB`.
    let pointsIOB: [PointIOB]

    /// Insuline active (IOB — Insulin On Board) au moment courant.
    /// **Computed** depuis `pointsIOB.first` pour garantir que la
    /// valeur affichée sur la carte et le marqueur "maintenant" du
    /// graphique reposent sur la même source de vérité.
    var iob: Double {
        pointsIOB.first?.iob ?? 0
    }
}

// MARK: - Service

/// Service mocké pour la grille de métriques d'accueil.
///
/// Source de vérité unique pour les 4 cartes — toutes les vues piochent
/// dans `metriques`. Les méthodes statiques `mock*` exposent des jeux
/// prêts à l'emploi pour les previews (états normal / alerte / calme).
///
/// Branchera l'API NestJS plus tard (endpoint d'agrégation côté
/// backend) ; l'API publique (`metriques`) reste stable.
@Observable
@MainActor
final class AccueilMetriquesServiceMock {

    static let shared = AccueilMetriquesServiceMock(metriques: .mockNormal)

    /// Snapshot courant. Lecture seule depuis l'extérieur — la couche
    /// d'analyses sera la seule à pouvoir le ré-écrire.
    private(set) var metriques: MetriquesAccueil

    init(metriques: MetriquesAccueil) {
        self.metriques = metriques
    }
}

// MARK: - Mocks pré-configurés

extension MetriquesAccueil {

    /// Journée typique sans incident : 0 hypo, IOB élevé en milieu de
    /// digestion (~3.4u — 4u il y a 2h + 1.5u il y a 45min), dernière
    /// injection il y a 2h13, repas modéré.
    static let mockNormal: MetriquesAccueil = {
        let now = Date()
        let injections = [
            InjectionPourIOB(heure: now.addingTimeInterval(-2 * 3600), dose: 4.0),
            InjectionPourIOB(heure: now.addingTimeInterval(-45 * 60), dose: 1.5),
        ]
        return MetriquesAccueil(
            hyposAujourdhui: 0,
            hyposSeveres: 0,
            hyposLegeres: 0,
            derniereInjectionDose: 4.0,
            derniereInjectionDepuis: 60 * 60 * 2 + 60 * 13, // 2h13
            derniereInjectionType: .rapide,
            dernierRepasGlucides: 45,
            dernierRepasDepuis: 60 * 60 * 2 + 60 * 18, // 2h18 (un peu après l'injection bolus)
            dernierRepasEmojis: ["🍞", "🧀", "🥛"],
            pointsCgmJournee: cgmJournee(avecHypos: false),
            pointsIOB: courbeIOB(injections: injections, debut: now)
        )
    }()

    /// Journée à risque : 2 hypos (1 sévère ~46 mg/dL à 09h15, 1
    /// légère ~61 mg/dL à 14h30), IOB encore élevé (~4.4u — 4u il y a
    /// 1h30 + 2u il y a 30min) — exerce la palette d'alerte.
    static let mockAlerte: MetriquesAccueil = {
        let now = Date()
        let injections = [
            InjectionPourIOB(heure: now.addingTimeInterval(-90 * 60), dose: 4.0),
            InjectionPourIOB(heure: now.addingTimeInterval(-30 * 60), dose: 2.0),
        ]
        return MetriquesAccueil(
            hyposAujourdhui: 2,
            hyposSeveres: 1,
            hyposLegeres: 1,
            derniereInjectionDose: 6.5,
            derniereInjectionDepuis: 60 * 60 + 60 * 5, // 1h05
            derniereInjectionType: .rapide,
            dernierRepasGlucides: 72,
            dernierRepasDepuis: 60 * 60 + 60 * 8, // 1h08
            dernierRepasEmojis: ["🍝", "🧀", "🥖"],
            pointsCgmJournee: cgmJournee(avecHypos: true),
            pointsIOB: courbeIOB(injections: injections, debut: now)
        )
    }()

    /// Journée calme : 0 hypo, IOB résiduel quasi nul (3.5u il y a 3h30
    /// → ~0.44u restant), dernière injection une **lente** prise il y
    /// a 8h (12u Lantus typique) — scénario "rien d'actif" qui exerce
    /// les cartes en mode calme et met en avant le badge bleu lente.
    static let mockCalme: MetriquesAccueil = {
        let now = Date()
        let injections = [
            InjectionPourIOB(heure: now.addingTimeInterval(-3.5 * 3600), dose: 3.5),
        ]
        return MetriquesAccueil(
            hyposAujourdhui: 0,
            hyposSeveres: 0,
            hyposLegeres: 0,
            derniereInjectionDose: 12,
            derniereInjectionDepuis: 60 * 60 * 8, // 8h
            derniereInjectionType: .lente,
            dernierRepasGlucides: 28,
            dernierRepasDepuis: 60 * 60 * 6, // 6h
            dernierRepasEmojis: ["🥗", "🥑"],
            pointsCgmJournee: cgmJournee(avecHypos: false),
            pointsIOB: courbeIOB(injections: injections, debut: now)
        )
    }()
}

// MARK: - Générateur CGM 24h

/// Modèle simplifié d'une journée CGM (48 points, 1 toutes les 30min).
///
/// Profil typique : baseline plus haute en journée (~125-150 mg/dL),
/// creux nocturnes (~100), ondulations post-prandiales superposées.
/// Quand `avecHypos == true`, on surimprime deux gaussiennes
/// d'hypoglycémie : sévère à 09h15 (~46 mg/dL au creux) et légère à
/// 14h30 (~61 mg/dL au creux).
///
/// Le résultat est borné [40, 280] pour rester dans une fenêtre
/// physiologiquement plausible et éviter les artefacts visuels en
/// bout de courbe.
private func cgmJournee(avecHypos: Bool) -> [LectureCgm] {
    let cal = Calendar.current
    let debutJour = cal.startOfDay(for: Date())

    return (0..<48).map { i in
        let minutes = i * 30
        let heure = cal.date(byAdding: .minute, value: minutes, to: debutJour) ?? debutJour
        let h = Double(minutes) / 60.0

        // Baseline diurne — combinaison de deux sinusoïdes pour éviter
        // un profil "ressort" trop régulier. Première vague large
        // (période ~24h) module le nuit-jour ; deuxième vague rapide
        // (période ~6h) suggère les ondulations post-prandiales.
        var valeur = 125.0
            + 25 * sin((h - 6) * .pi / 12)
            + 12 * sin(h * .pi / 3)

        if avecHypos {
            // Hypo sévère à 09h15 — gaussienne étroite, ~46 mg/dL au creux.
            let d1 = abs(h - 9.25)
            valeur -= 95 * exp(-pow(d1 * 1.6, 2))
            // Hypo légère à 14h30 — gaussienne similaire, ~61 mg/dL au creux.
            let d2 = abs(h - 14.5)
            valeur -= 90 * exp(-pow(d2 * 1.6, 2))
        }

        return LectureCgm(heure: heure, valeur: max(40, min(280, valeur)))
    }
}

// MARK: - Calcul IOB (modèle bicubique lisse)

/// IOB résiduel d'une **injection unique** au temps `minutesEcoulees`
/// depuis l'injection, exprimé en unités. Modèle **bicubique Hermite**
/// — deux cubiques smoothstep raccordées au pic d'activité avec
/// dérivée nulle des deux côtés :
///
///   - **0 → pic** : phase d'absorption. IOB descend de `dose` à
///     `0.6 × dose` en suivant `1 - 0.4·smoothstep(t/pic)`. Pente
///     nulle à l'origine (l'insuline n'a pas encore atteint la
///     circulation) puis accélération vers le pic.
///   - **pic → DIA** : phase de consommation. IOB descend de
///     `0.6 × dose` à 0 en suivant `0.6·(1 - smoothstep((t-pic)/(DIA-pic)))`.
///     Pente nulle à DIA (asymptote propre — pas de coupure brutale).
///
/// `smoothstep(u) = u²(3 - 2u)` a une dérivée nulle aux deux
/// extrémités, donc la fonction globale est **C¹ partout** (continue
/// et dérivable, y compris au pic). C'est ce qui fait que la somme
/// de plusieurs injections produit une courbe lisse — sans le "kink"
/// d'un modèle piecewise-linéaire qui apparaissait à chaque transition.
///
/// **Paramètres par défaut** : DIA = 240min (4h), pic à 75min — calés
/// sur un analogue rapide moderne (NovoRapid, Humalog). Pour une
/// ultra-rapide (Fiasp, Lyumjev), passer `pic: 55, dia: 210`.
///
/// Au-delà de DIA, IOB = 0 — l'injection est consommée.
private func iobResiduel(
    dose: Double,
    minutesEcoulees: Double,
    dia: Double = 240,
    pic: Double = 75
) -> Double {
    guard minutesEcoulees >= 0 else { return dose }
    guard minutesEcoulees < dia else { return 0 }

    // Cubique de Hermite : `u²(3 - 2u)`, 0 → 1 avec dérivée nulle aux
    // deux extrémités. Une seule définition réutilisée des deux côtés
    // du pic — c'est ce qui garantit la continuité de la dérivée.
    func smoothstep(_ u: Double) -> Double {
        u * u * (3 - 2 * u)
    }

    if minutesEcoulees <= pic {
        // Phase d'absorption : 40 % de la dose consommés entre 0 et pic.
        let u = minutesEcoulees / pic
        return dose * (1 - 0.4 * smoothstep(u))
    }
    // Phase de consommation : les 60 % restants entre pic et DIA.
    let u = (minutesEcoulees - pic) / (dia - pic)
    return dose * 0.6 * (1 - smoothstep(u))
}

/// Courbe d'IOB **total** (somme des résidus de toutes les injections
/// actives) sur les 6h à venir, échantillonnée toutes les 15min.
///
/// Comme `iobResiduel` est C¹ partout, la somme l'est aussi : la
/// courbe reste lisse quelles que soient les injections superposées
/// — pas de cassure visible à la transition pic / consommation de
/// chaque bolus, même quand ils s'enchaînent à 30min d'intervalle.
///
/// La courbe s'arrête quand l'IOB descend sous 0.05u — pas la peine
/// de tracer une queue plate à zéro qui prendrait la moitié de la
/// largeur du chart. Le premier point (minutes = 0) correspond à
/// "maintenant" et fournit la valeur affichée sur la carte (via
/// `MetriquesAccueil.iob`).
private func courbeIOB(injections: [InjectionPourIOB], debut: Date) -> [PointIOB] {
    var points: [PointIOB] = []
    for minutes in stride(from: 0, through: 360, by: 15) {
        let date = debut.addingTimeInterval(Double(minutes) * 60)
        let iob = injections.reduce(0.0) { total, injection in
            let elapsed = date.timeIntervalSince(injection.heure) / 60
            return total + iobResiduel(dose: injection.dose, minutesEcoulees: elapsed)
        }
        points.append(PointIOB(minutesDepuisMaintenant: minutes, iob: iob))
        // Coupure de queue : dès que la courbe est plate à zéro, on
        // arrête (sauf au tout premier échantillon, qui doit toujours
        // exister pour ancrer le marqueur "maintenant").
        if iob < 0.05 && minutes > 0 { break }
    }
    return points
}
