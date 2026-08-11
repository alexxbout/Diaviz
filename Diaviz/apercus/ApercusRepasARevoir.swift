//
//  ApercusRepasARevoir.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

#if DEBUG

import Foundation

// MARK: - Aperçus


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
        glucidesMax: 70,
        libelleSection: "Déjeuner",
        ratioApplique: 11,
        evenements: [
            EvenementCourbe(genre: .bolusRepas, minutes: 0, libelle: "10,5 u"),
            EvenementCourbe(genre: .correction, minutes: 105, libelle: "2 u"),
        ]
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
        glucidesMax: 95,
        libelleSection: "Dîner",
        ratioApplique: 9,
        evenements: [
            EvenementCourbe(genre: .bolusRepas, minutes: 0, libelle: "8,5 u"),
            EvenementCourbe(genre: .lente, minutes: 150, libelle: "18 u"),
        ]
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
        glucidesMax: 75,
        libelleSection: "Dîner",
        ratioApplique: 10,
        evenements: [
            EvenementCourbe(genre: .bolusRepas, minutes: 0, libelle: "6,5 u"),
            EvenementCourbe(genre: .sport, minutes: 30, dureeMinutes: 45, libelle: "Marche 45 min"),
            EvenementCourbe(genre: .repas, minutes: 135, libelle: "15 g"),
        ]
    )
}

#endif
