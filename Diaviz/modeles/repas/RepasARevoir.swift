//
//  RepasARevoir.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation
import SwiftUI

// MARK: - Point de courbe

/// Point unique d'une courbe de réponse glycémique post-repas, indexé
/// en **minutes** depuis T0 (instant du repas). Granularité ~15 min
/// sur 3h, avec des points intermédiaires possibles pour caler
/// exactement les pics (qui ne tombent pas toujours sur la grille).
struct PointCourbeRepas: Identifiable, Sendable {
    let id = UUID()
    /// Minutes depuis T0 (0 = instant du repas).
    let minutes: Int
    /// Glycémie en mg/dL.
    let glycemie: Double
}

// MARK: - RepasARevoir

/// Repas signalé comme « à revoir » sur l'accueil : au moins un
/// aliment a un flag glucides incertains et la réponse glycémique
/// est sortie de cible, hors fenêtre de sport.
///
/// Le modèle porte **toutes** les courbes des occurrences passées
/// (au lieu d'une seule courbe moyenne) — ça permet à la carte de
/// montrer visuellement la **dispersion** des réponses : courbes
/// regroupées = repas prévisible, courbes étalées = repas chaotique.
struct RepasARevoir: Identifiable {
    let id = UUID()

    /// Aliments du repas. L'aliment le plus glucidique pilote l'emoji
    /// et le nom affichés en titre de la carte.
    let aliments: [Aliment]

    /// Nombre total de fois où ce repas (composition équivalente) a
    /// été enregistré dans l'historique. Compte la dernière fois
    /// incluse — `pointsOccurrencesPassees.count + 1` doit être égal
    /// à cette valeur.
    let nombreOccurrences: Int

    /// Toutes les courbes des occurrences passées **sauf** la dernière.
    /// Chacune est rendue en gris discret dans le mini-chart pour
    /// donner une impression de nuage / dispersion. Si le tableau est
    /// vide (un seul enregistrement total), seule la courbe colorée
    /// « dernière fois » apparaît.
    let pointsOccurrencesPassees: [[PointCourbeRepas]]

    /// Courbe de la dernière occurrence — celle qui motive le
    /// « à revoir ». Affichée en trait plein dans la couleur de sévérité.
    let pointsDerniereFois: [PointCourbeRepas]

    /// Minutes depuis T0 de l'événement principal (pic max ou minimum
    /// en cas d'hypo) sur la courbe « dernière fois ».
    let evenementMinutes: Int

    /// Valeur en mg/dL de l'événement principal.
    let evenementValeur: Double

    /// `true` si l'événement principal est une hypo (< 70 mg/dL) plutôt
    /// qu'un pic en hyper. Pilote le triangle ▼ et le libellé « Hypo ».
    let estHypo: Bool

    /// Fourchette de glucides déclarés sur toutes les occurrences de ce
    /// repas — l'écart reflète l'incertitude liée aux aliments estimés.
    let glucidesMin: Int
    let glucidesMax: Int

    // MARK: Computed

    /// Aliment le plus contributeur en glucides — celui qui pilote la
    /// réponse glycémique et qui sert d'emoji / nom de titre.
    var alimentPrincipal: Aliment? {
        aliments.max(by: { $0.glucides < $1.glucides })
    }

    /// `true` si **n'importe quelle** courbe (passée ou dernière fois)
    /// descend sous le seuil d'hypo 70 mg/dL. Pilote l'affichage
    /// conditionnel du `RuleMark` rouge à 70 dans le chart : pas la
    /// peine de tracer la ligne si aucune courbe ne s'en approche.
    var aHypoDansCourbes: Bool {
        let toutesValeurs = pointsDerniereFois.map(\.glycemie)
            + pointsOccurrencesPassees.flatMap { $0.map(\.glycemie) }
        return toutesValeurs.contains { $0 < 70 }
    }

    /// Couleur de sévérité appliquée à la courbe « dernière fois », au
    /// PointMark du pic et à l'info pic textuelle.
    ///
    /// Règles (cohérentes avec les seuils cible/hyper/hyper sévère) :
    /// - Hypo (< 70) → rouge
    /// - En cible (pic < 180) → vert
    /// - Hyper (180–250) → orange
    /// - Hyper sévère (> 250) → rouge
    var couleurSeverite: Color {
        if estHypo { return .red }
        if evenementValeur < 180 { return .green }
        if evenementValeur <= 250 { return .orange }
        return .red
    }

    /// Libellé compact de l'info pic — « Pic 235 · après 1h15 » ou
    /// « Hypo 62 · après 2h00 » selon la nature de l'événement.
    var libelleEvenement: String {
        let label = estHypo ? "Hypo" : "Pic"
        return "\(label) \(Int(evenementValeur.rounded())) · après \(formatHeureMinutes(evenementMinutes))"
    }

    /// Triangle directionnel pour l'info pic : ▲ pour un hyper,
    /// ▼ pour une hypo.
    var symboleEvenement: String {
        estHypo ? "▼" : "▲"
    }

    /// Format « 1h15 » ou « 45 min » pour la durée depuis le repas.
    private func formatHeureMinutes(_ minutes: Int) -> String {
        let heures = minutes / 60
        let reste = minutes % 60
        if heures == 0 { return "\(reste) min" }
        return "\(heures)h\(String(format: "%02d", reste))"
    }
}

// MARK: - Mocks

extension RepasARevoir {

    /// Big Mac — hyper modéré (235 mg/dL), 5 occurrences (4 courbes
    /// passées en nuage gris + 1 colorée orange). Glucides 55–70g.
    static let mockBigMac = RepasARevoir(
        aliments: [
            Aliment(emoji: "🍔", nom: "Big Mac", quantite: 220, glucides: 45, insuline: 4.5),
            Aliment(emoji: "🍟", nom: "Frites moyennes", quantite: 110, glucides: 42, insuline: 3.5),
            Aliment(emoji: "🥤", nom: "Coca", quantite: 250, glucides: 27, insuline: 2.5),
        ],
        nombreOccurrences: 5,
        pointsOccurrencesPassees: [
            // 4 occurrences passées, peaks 185–220, échelonnés sur
            // 60–85 min — dispersion modérée, repas "presque
            // prévisible" sauf la dernière fois.
            [
                PointCourbeRepas(minutes: 0,   glycemie: 105),
                PointCourbeRepas(minutes: 15,  glycemie: 118),
                PointCourbeRepas(minutes: 30,  glycemie: 142),
                PointCourbeRepas(minutes: 45,  glycemie: 168),
                PointCourbeRepas(minutes: 60,  glycemie: 185),
                PointCourbeRepas(minutes: 75,  glycemie: 195),
                PointCourbeRepas(minutes: 90,  glycemie: 188),
                PointCourbeRepas(minutes: 105, glycemie: 170),
                PointCourbeRepas(minutes: 120, glycemie: 150),
                PointCourbeRepas(minutes: 135, glycemie: 132),
                PointCourbeRepas(minutes: 150, glycemie: 120),
                PointCourbeRepas(minutes: 165, glycemie: 112),
                PointCourbeRepas(minutes: 180, glycemie: 108),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 112),
                PointCourbeRepas(minutes: 15,  glycemie: 125),
                PointCourbeRepas(minutes: 30,  glycemie: 152),
                PointCourbeRepas(minutes: 45,  glycemie: 178),
                PointCourbeRepas(minutes: 60,  glycemie: 200),
                PointCourbeRepas(minutes: 75,  glycemie: 210),
                PointCourbeRepas(minutes: 90,  glycemie: 205),
                PointCourbeRepas(minutes: 105, glycemie: 188),
                PointCourbeRepas(minutes: 120, glycemie: 165),
                PointCourbeRepas(minutes: 135, glycemie: 145),
                PointCourbeRepas(minutes: 150, glycemie: 128),
                PointCourbeRepas(minutes: 165, glycemie: 118),
                PointCourbeRepas(minutes: 180, glycemie: 112),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 100),
                PointCourbeRepas(minutes: 15,  glycemie: 112),
                PointCourbeRepas(minutes: 30,  glycemie: 132),
                PointCourbeRepas(minutes: 45,  glycemie: 158),
                PointCourbeRepas(minutes: 60,  glycemie: 178),
                PointCourbeRepas(minutes: 75,  glycemie: 182),
                PointCourbeRepas(minutes: 90,  glycemie: 172),
                PointCourbeRepas(minutes: 105, glycemie: 155),
                PointCourbeRepas(minutes: 120, glycemie: 138),
                PointCourbeRepas(minutes: 135, glycemie: 125),
                PointCourbeRepas(minutes: 150, glycemie: 115),
                PointCourbeRepas(minutes: 165, glycemie: 108),
                PointCourbeRepas(minutes: 180, glycemie: 105),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 115),
                PointCourbeRepas(minutes: 15,  glycemie: 128),
                PointCourbeRepas(minutes: 30,  glycemie: 158),
                PointCourbeRepas(minutes: 45,  glycemie: 188),
                PointCourbeRepas(minutes: 60,  glycemie: 210),
                PointCourbeRepas(minutes: 75,  glycemie: 218),
                PointCourbeRepas(minutes: 90,  glycemie: 215),
                PointCourbeRepas(minutes: 105, glycemie: 198),
                PointCourbeRepas(minutes: 120, glycemie: 172),
                PointCourbeRepas(minutes: 135, glycemie: 148),
                PointCourbeRepas(minutes: 150, glycemie: 130),
                PointCourbeRepas(minutes: 165, glycemie: 118),
                PointCourbeRepas(minutes: 180, glycemie: 110),
            ],
        ],
        pointsDerniereFois: [
            PointCourbeRepas(minutes: 0,   glycemie: 110),
            PointCourbeRepas(minutes: 15,  glycemie: 130),
            PointCourbeRepas(minutes: 30,  glycemie: 165),
            PointCourbeRepas(minutes: 45,  glycemie: 195),
            PointCourbeRepas(minutes: 60,  glycemie: 220),
            PointCourbeRepas(minutes: 75,  glycemie: 235),
            PointCourbeRepas(minutes: 90,  glycemie: 225),
            PointCourbeRepas(minutes: 105, glycemie: 200),
            PointCourbeRepas(minutes: 120, glycemie: 175),
            PointCourbeRepas(minutes: 135, glycemie: 150),
            PointCourbeRepas(minutes: 150, glycemie: 130),
            PointCourbeRepas(minutes: 165, glycemie: 115),
            PointCourbeRepas(minutes: 180, glycemie: 108),
        ],
        evenementMinutes: 75,
        evenementValeur: 235,
        estHypo: false,
        glucidesMin: 55,
        glucidesMax: 70
    )

    /// Pizza Margherita + Tiramisu — hyper sévère (265 mg/dL),
    /// 3 occurrences (2 courbes passées + 1 dernière fois). Glucides
    /// 80–95g. Pic décalé tardivement (1h40) caractéristique des
    /// repas riches en graisses.
    static let mockPizza = RepasARevoir(
        aliments: [
            Aliment(emoji: "🍕", nom: "Pizza Margherita", quantite: 350, glucides: 65, insuline: 6.0),
            Aliment(emoji: "🍰", nom: "Tiramisu", quantite: 120, glucides: 28, insuline: 2.5),
        ],
        nombreOccurrences: 3,
        pointsOccurrencesPassees: [
            // 2 courbes passées, peaks 220–235 — moins haut que la
            // dernière fois mais toujours dans la zone hyper.
            [
                PointCourbeRepas(minutes: 0,   glycemie: 110),
                PointCourbeRepas(minutes: 15,  glycemie: 125),
                PointCourbeRepas(minutes: 30,  glycemie: 150),
                PointCourbeRepas(minutes: 45,  glycemie: 178),
                PointCourbeRepas(minutes: 60,  glycemie: 200),
                PointCourbeRepas(minutes: 75,  glycemie: 215),
                PointCourbeRepas(minutes: 90,  glycemie: 220),
                PointCourbeRepas(minutes: 105, glycemie: 212),
                PointCourbeRepas(minutes: 120, glycemie: 195),
                PointCourbeRepas(minutes: 135, glycemie: 175),
                PointCourbeRepas(minutes: 150, glycemie: 158),
                PointCourbeRepas(minutes: 165, glycemie: 142),
                PointCourbeRepas(minutes: 180, glycemie: 130),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 115),
                PointCourbeRepas(minutes: 15,  glycemie: 130),
                PointCourbeRepas(minutes: 30,  glycemie: 158),
                PointCourbeRepas(minutes: 45,  glycemie: 188),
                PointCourbeRepas(minutes: 60,  glycemie: 215),
                PointCourbeRepas(minutes: 75,  glycemie: 230),
                PointCourbeRepas(minutes: 90,  glycemie: 235),
                PointCourbeRepas(minutes: 105, glycemie: 225),
                PointCourbeRepas(minutes: 120, glycemie: 208),
                PointCourbeRepas(minutes: 135, glycemie: 188),
                PointCourbeRepas(minutes: 150, glycemie: 168),
                PointCourbeRepas(minutes: 165, glycemie: 150),
                PointCourbeRepas(minutes: 180, glycemie: 138),
            ],
        ],
        pointsDerniereFois: [
            PointCourbeRepas(minutes: 0,   glycemie: 115),
            PointCourbeRepas(minutes: 15,  glycemie: 135),
            PointCourbeRepas(minutes: 30,  glycemie: 165),
            PointCourbeRepas(minutes: 45,  glycemie: 195),
            PointCourbeRepas(minutes: 60,  glycemie: 225),
            PointCourbeRepas(minutes: 75,  glycemie: 248),
            PointCourbeRepas(minutes: 90,  glycemie: 260),
            // Point exact du pic, hors grille 15 min, pour caler le
            // PointMark dans la chart sans dépendre de l'interpolation.
            PointCourbeRepas(minutes: 100, glycemie: 265),
            PointCourbeRepas(minutes: 120, glycemie: 255),
            PointCourbeRepas(minutes: 135, glycemie: 235),
            PointCourbeRepas(minutes: 150, glycemie: 215),
            PointCourbeRepas(minutes: 165, glycemie: 198),
            PointCourbeRepas(minutes: 180, glycemie: 180),
        ],
        evenementMinutes: 100,
        evenementValeur: 265,
        estHypo: false,
        glucidesMin: 80,
        glucidesMax: 95
    )

    /// California roll — pic en cible (175 mg/dL), 2 occurrences
    /// (1 courbe passée + 1 dernière fois). Glucides 40–50g.
    /// Réponse rapide et plafonnée → couleur verte.
    static let mockSushi = RepasARevoir(
        aliments: [
            Aliment(emoji: "🍣", nom: "California roll", quantite: 200, glucides: 38, insuline: 3.5),
            Aliment(emoji: "🍲", nom: "Soupe miso", quantite: 200, glucides: 4, insuline: 0.0),
            Aliment(emoji: "🌱", nom: "Edamame", quantite: 100, glucides: 8, insuline: 0.5),
        ],
        nombreOccurrences: 2,
        pointsOccurrencesPassees: [
            // 1 seule courbe passée — peak doux 165 à 60 min,
            // très proche de la dernière fois (repas régulier).
            [
                PointCourbeRepas(minutes: 0,   glycemie: 100),
                PointCourbeRepas(minutes: 15,  glycemie: 112),
                PointCourbeRepas(minutes: 30,  glycemie: 135),
                PointCourbeRepas(minutes: 45,  glycemie: 155),
                PointCourbeRepas(minutes: 60,  glycemie: 165),
                PointCourbeRepas(minutes: 75,  glycemie: 158),
                PointCourbeRepas(minutes: 90,  glycemie: 145),
                PointCourbeRepas(minutes: 105, glycemie: 132),
                PointCourbeRepas(minutes: 120, glycemie: 120),
                PointCourbeRepas(minutes: 135, glycemie: 112),
                PointCourbeRepas(minutes: 150, glycemie: 105),
                PointCourbeRepas(minutes: 165, glycemie: 102),
                PointCourbeRepas(minutes: 180, glycemie: 100),
            ],
        ],
        pointsDerniereFois: [
            PointCourbeRepas(minutes: 0,   glycemie: 105),
            PointCourbeRepas(minutes: 15,  glycemie: 120),
            PointCourbeRepas(minutes: 30,  glycemie: 145),
            PointCourbeRepas(minutes: 45,  glycemie: 168),
            // Pic à 55 min, hors grille 15 min.
            PointCourbeRepas(minutes: 55,  glycemie: 175),
            PointCourbeRepas(minutes: 75,  glycemie: 165),
            PointCourbeRepas(minutes: 90,  glycemie: 150),
            PointCourbeRepas(minutes: 105, glycemie: 138),
            PointCourbeRepas(minutes: 120, glycemie: 125),
            PointCourbeRepas(minutes: 135, glycemie: 118),
            PointCourbeRepas(minutes: 150, glycemie: 112),
            PointCourbeRepas(minutes: 165, glycemie: 108),
            PointCourbeRepas(minutes: 180, glycemie: 105),
        ],
        evenementMinutes: 55,
        evenementValeur: 175,
        estHypo: false,
        glucidesMin: 40,
        glucidesMax: 50
    )

    /// Pad Thaï — hypo post-prandiale (62 mg/dL à T+2h), 3 occurrences.
    /// Glucides 60–75g. Pattern typique d'un surdosage d'insuline
    /// sur des glucides estimés trop haut : la courbe monte
    /// modérément à 140 puis plonge en hypo deux heures après —
    /// l'insuline continue d'agir alors que les glucides sont
    /// digérés. Couleur rouge (hypo).
    static let mockPadThai = RepasARevoir(
        aliments: [
            Aliment(emoji: "🍜", nom: "Pad Thaï", quantite: 380, glucides: 68, insuline: 6.5),
            Aliment(emoji: "🥜", nom: "Cacahuètes", quantite: 20, glucides: 4, insuline: 0.0),
        ],
        nombreOccurrences: 3,
        pointsOccurrencesPassees: [
            // 2 courbes passées qui oscillent doucement autour de
            // 120–150, sans franchir la cible — ce sont les "bonnes"
            // expériences précédentes qui rendent la dernière fois
            // d'autant plus surprenante.
            [
                PointCourbeRepas(minutes: 0,   glycemie: 115),
                PointCourbeRepas(minutes: 15,  glycemie: 125),
                PointCourbeRepas(minutes: 30,  glycemie: 138),
                PointCourbeRepas(minutes: 45,  glycemie: 145),
                PointCourbeRepas(minutes: 60,  glycemie: 142),
                PointCourbeRepas(minutes: 75,  glycemie: 138),
                PointCourbeRepas(minutes: 90,  glycemie: 132),
                PointCourbeRepas(minutes: 105, glycemie: 128),
                PointCourbeRepas(minutes: 120, glycemie: 125),
                PointCourbeRepas(minutes: 135, glycemie: 122),
                PointCourbeRepas(minutes: 150, glycemie: 120),
                PointCourbeRepas(minutes: 165, glycemie: 118),
                PointCourbeRepas(minutes: 180, glycemie: 115),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 120),
                PointCourbeRepas(minutes: 15,  glycemie: 128),
                PointCourbeRepas(minutes: 30,  glycemie: 142),
                PointCourbeRepas(minutes: 45,  glycemie: 150),
                PointCourbeRepas(minutes: 60,  glycemie: 148),
                PointCourbeRepas(minutes: 75,  glycemie: 145),
                PointCourbeRepas(minutes: 90,  glycemie: 138),
                PointCourbeRepas(minutes: 105, glycemie: 132),
                PointCourbeRepas(minutes: 120, glycemie: 128),
                PointCourbeRepas(minutes: 135, glycemie: 125),
                PointCourbeRepas(minutes: 150, glycemie: 122),
                PointCourbeRepas(minutes: 165, glycemie: 120),
                PointCourbeRepas(minutes: 180, glycemie: 118),
            ],
        ],
        pointsDerniereFois: [
            // Montée modérée à 140 sur 60 min puis plongée en hypo :
            // T+2h = 62 mg/dL (point exact pour caler le PointMark),
            // récupération graduelle ensuite (resucrage implicite).
            PointCourbeRepas(minutes: 0,   glycemie: 118),
            PointCourbeRepas(minutes: 15,  glycemie: 125),
            PointCourbeRepas(minutes: 30,  glycemie: 132),
            PointCourbeRepas(minutes: 45,  glycemie: 138),
            PointCourbeRepas(minutes: 60,  glycemie: 140),
            PointCourbeRepas(minutes: 75,  glycemie: 130),
            PointCourbeRepas(minutes: 90,  glycemie: 112),
            PointCourbeRepas(minutes: 105, glycemie: 88),
            PointCourbeRepas(minutes: 120, glycemie: 62),
            PointCourbeRepas(minutes: 135, glycemie: 72),
            PointCourbeRepas(minutes: 150, glycemie: 88),
            PointCourbeRepas(minutes: 165, glycemie: 102),
            PointCourbeRepas(minutes: 180, glycemie: 112),
        ],
        evenementMinutes: 120,
        evenementValeur: 62,
        estHypo: true,
        glucidesMin: 60,
        glucidesMax: 75
    )
}
