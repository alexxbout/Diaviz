//
//  ReponseGlycemiqueServiceMock.swift
//  diaviz
//
//  Created by Alexandre on 30/04/2026.
//

import Foundation

// MARK: - ReponseGlycemiqueServiceMock
//
// Génère des `ReponseGlycemique` synthétiques pour les previews et la
// validation visuelle. Toutes les courbes sont déterministes : pas de
// `random` — pour avoir des previews stables et comparables d'un build
// à l'autre. Quand l'API backend sera branchée, ce service sera remplacé
// par un vrai client réseau ; la signature publique restera la même
// (Repas → EtatAnalyse).
enum ReponseGlycemiqueServiceMock {

    // Typealias dédié pour les points-clés des courbes complexes. Sans ça,
    // le type-checker SwiftUI prend plusieurs secondes (ou échoue avec
    // "unable to type-check in reasonable time") sur les literal arrays
    // de tuples nommés `[(minutes: Double, valeur: Double)]`.
    typealias PointCleCourbe = (minutes: Double, valeur: Double)

    // MARK: Paramètres globaux

    /// Pas d'échantillonnage en secondes (5 minutes — résolution typique du
    /// CGM Dexcom ONE+).
    private static let pasEchantillonnage: TimeInterval = 5 * 60
    /// Fenêtre d'observation : T-1h à T+4h.
    private static let debutFenetre: TimeInterval = -3600
    private static let finFenetre: TimeInterval = 4 * 3600

    // MARK: Points-clés des courbes complexes
    //
    // Extraits en constantes top-level explicitement typées : sinon le
    // type-checker SwiftUI met plusieurs secondes (ou échoue) à inférer
    // ces literals à l'intérieur du `switch` de `cas(_:)`.

    private static let pointsHypoApresPic: [PointCleCourbe] = [
        (-60, 112), (-30, 110), (0, 110),
        (30, 175), (60, 195), (90, 175),
        (120, 140), (150, 105), (180, 80),
        (210, 65), (240, 60), (270, 70),
        (300, 85), (360, 95), (420, 100),
    ]

    private static let pointsHypoTardive: [PointCleCourbe] = [
        (-60, 108), (-30, 105), (0, 105),
        (30, 125), (60, 140), (90, 135),
        (120, 125), (150, 115), (180, 105),
        (210, 95), (240, 85), (270, 75),
        (300, 70), (360, 62), (420, 65),
    ]

    private static let pointsDoublePic: [PointCleCourbe] = [
        (-60, 110), (-30, 108), (0, 110),
        (30, 175), (60, 195), (90, 170),
        (120, 150), (150, 165), (180, 185),
        (210, 175), (240, 155), (300, 140),
        (360, 130), (420, 125),
    ]

    private static let pointsPlateauHaut: [PointCleCourbe] = [
        (-60, 132), (-30, 130), (0, 130),
        (30, 160), (60, 195), (90, 230),
        (120, 235), (150, 230), (180, 225),
        (210, 220), (240, 215), (300, 208),
        (360, 200), (420, 195),
    ]

    private static let pointsDepartHyper: [PointCleCourbe] = [
        (-60, 215), (-30, 218), (0, 220),
        (30, 250), (60, 275), (90, 285),
        (120, 270), (150, 255), (180, 240),
        (210, 225), (240, 215), (300, 205),
        (360, 200), (420, 198),
    ]

    private static let pointsCorrectionReussie: [PointCleCourbe] = [
        (-60, 195), (-30, 200), (0, 200),
        (30, 215), (60, 235), (90, 220),
        (120, 195), (150, 170), (180, 150),
        (210, 135), (240, 125), (300, 120),
        (360, 125), (420, 130),
    ]

    private static let pointsCorrectionEchouee: [PointCleCourbe] = [
        (-60, 230), (-30, 235), (0, 240),
        (30, 270), (60, 285), (90, 280),
        (120, 270), (150, 262), (180, 255),
        (210, 248), (240, 242), (300, 235),
        (360, 230), (420, 228),
    ]

    private static let pointsMontagneRusse: [PointCleCourbe] = [
        (-60, 115), (-30, 110), (0, 110),
        (30, 180), (60, 230), (90, 245),
        (120, 200), (150, 130), (180, 80),
        (210, 65), (240, 80), (270, 120),
        (300, 165), (360, 175), (420, 160),
    ]

    // MARK: API publique

    /// Génère les cas standards utilisés pour exercer toutes les variantes
    /// de la `LigneRepas`. Les valeurs numériques sont calibrées pour
    /// que les verdicts soient visuellement distincts dans la mini-courbe :
    ///
    /// **Verdicts standards (forme classique mono-pic) :**
    /// - bon     : départ 110 → pic 165 à T+1h    → 130 à T+3h (sous la cible)
    /// - moyen   : départ 130 → pic 215 à T+1h15  → 160 à T+3h30 (retour limite)
    /// - mauvais : départ 145 → pic 265 à T+1h30  → encore 220 à T+4h (pas de retour)
    ///
    /// **Variations de forme — bas :**
    /// - hypoApresPic : pic puis hypo à 60 vers T+3h (correction trop forte)
    /// - hypoTardive  : descente continue vers 60 mg/dL en fin de fenêtre
    ///
    /// **Variations de forme — haut :**
    /// - doublePic    : repas mixte glucides + graisses (deux pics distincts)
    /// - plateauHaut  : montée lente, plateau prolongé sans redescente franche
    ///
    /// **Départs en hyper (T0 > 180 mg/dL) :**
    /// - departHyper        : repas pris en hyper, pic à 285, descente lente
    /// - correctionReussie  : départ 200, correction qui ramène en cible (125)
    /// - correctionEchouee  : départ 240, correction inefficace, reste à 230
    ///
    /// **Mixtes :**
    /// - montagneRusse : pic 245 puis hypo 65 puis rebond hyper 175
    static func cas(_ cas: Cas) -> EtatAnalyse {
        switch cas {
        case .bon:
            return .disponible(courbe(
                verdict: .bon,
                glycemieT0: 110,
                valeurPic: 165,
                minutesPic: 60,
                minutesRetour: 180,
                valeurRetour: 130
            ))
        case .moyen:
            return .disponible(courbe(
                verdict: .moyen,
                glycemieT0: 130,
                valeurPic: 215,
                minutesPic: 75,
                minutesRetour: 210,
                valeurRetour: 160
            ))
        case .mauvais:
            return .disponible(courbe(
                verdict: .mauvais,
                glycemieT0: 145,
                valeurPic: 265,
                minutesPic: 90,
                minutesRetour: 240,
                valeurRetour: 220
            ))
        case .hypoApresPic:
            // Bolus surdosé : pic à 195 puis hypoglycémie marquée à T+3h30,
            // remontée après resucrage. Verdict mauvais — sortie de cible
            // par le bas, pas seulement par le haut.
            return .disponible(courbeParPoints(verdict: .mauvais, pointsCles: pointsHypoApresPic))
        case .hypoTardive:
            // Descente lente sans pic franc — typique d'une dose trop forte
            // sur un repas peu glucidique. Bascule en hypo en fin de fenêtre.
            return .disponible(courbeParPoints(verdict: .mauvais, pointsCles: pointsHypoTardive))
        case .doublePic:
            // Repas mixte (glucides rapides + graisses qui ralentissent la
            // digestion) : premier pic à T+1h, redescente partielle, second
            // pic plus tardif et plus modéré. Verdict moyen — le pic max
            // reste limité mais la sortie de cible dure longtemps.
            return .disponible(courbeParPoints(verdict: .moyen, pointsCles: pointsDoublePic))
        case .plateauHaut:
            // Glucides lents + gras élevé : montée graduelle vers un plateau
            // haut qui peine à redescendre dans la fenêtre. Verdict mauvais.
            return .disponible(courbeParPoints(verdict: .mauvais, pointsCles: pointsPlateauHaut))
        case .departHyper:
            // Repas pris alors qu'on est déjà en hyper (220 mg/dL). Le pic
            // monte à 285, puis longue redescente lente — on finit à 200,
            // toujours en hyper. Verdict mauvais.
            return .disponible(courbeParPoints(verdict: .mauvais, pointsCles: pointsDepartHyper))
        case .correctionReussie:
            // Départ en hyper modérée (200) + bolus de correction couvrant le
            // repas : pic limité à 235, redescente franche jusqu'à 125 en cible.
            // Verdict bon — l'objectif "rentrer en cible" est atteint.
            return .disponible(courbeParPoints(verdict: .bon, pointsCles: pointsCorrectionReussie))
        case .correctionEchouee:
            // Hyper marquée (240) avec correction sous-dosée : la courbe
            // monte à 285 puis stagne autour de 230. Pas de retour en cible.
            return .disponible(courbeParPoints(verdict: .mauvais, pointsCles: pointsCorrectionEchouee))
        case .montagneRusse:
            // Bolus mal calibré : gros pic à 245, plongée en hypo (65), puis
            // resucrage qui rebondit en hyper (175). Pic ET creux annotés.
            return .disponible(courbeParPoints(verdict: .mauvais, pointsCles: pointsMontagneRusse))
        case .enAttente:
            return .enAttente(minutesRestantes: 120)
        case .sansInjection:
            return .sansInjection
        case .donneesManquantes:
            return .donneesManquantes
        }
    }

    /// Cas de figure couverts par le mock — un par état visuel à valider.
    enum Cas: CaseIterable {
        // Verdicts standards (forme mono-pic)
        case bon
        case moyen
        case mauvais
        // Variations de forme — bas
        case hypoApresPic
        case hypoTardive
        // Variations de forme — haut
        case doublePic
        case plateauHaut
        // Départs en hyper
        case departHyper
        case correctionReussie
        case correctionEchouee
        // Mixtes
        case montagneRusse
        // États non-disponible
        case enAttente
        case sansInjection
        case donneesManquantes
    }

    // MARK: Génération de courbe

    /// Construit une courbe synthétique réaliste : plateau avant le repas,
    /// rampe ease-in jusqu'au pic, puis ease-out vers le point de retour
    /// (`valeurRetour` à `minutesRetour`), puis lente dérive vers le baseline.
    ///
    /// - Parameters:
    ///   - verdict: pilote uniquement la couleur du tracé.
    ///   - glycemieT0: valeur cible à l'instant du repas (T=0).
    ///   - valeurPic: glycémie maximale en mg/dL.
    ///   - minutesPic: délai (minutes) entre T0 et le pic. Multiple de 5 pour
    ///     tomber pile sur un échantillon — sinon le `PointMark` du pic ne
    ///     coïncide pas exactement avec la courbe.
    ///   - minutesRetour: instant (minutes après T0) du point de redescente.
    ///   - valeurRetour: glycémie à `minutesRetour`. Pilote la perception du
    ///     verdict : valeur basse = bonne récupération, valeur haute = mauvaise.
    private static func courbe(
        verdict: VerdictGlycemique,
        glycemieT0: Double,
        valeurPic: Double,
        minutesPic: Double,
        minutesRetour: Double,
        valeurRetour: Double
    ) -> ReponseGlycemique {
        let tempsPicSec = minutesPic * 60
        let tempsRetourSec = minutesRetour * 60
        var points: [PointCgm] = []

        // Itération par pas fixe : garantit un point exactement à T=0,
        // à `tempsPic` et à `tempsRetour` (les 3 valeurs sont multiples de 300s).
        var t = debutFenetre
        while t <= finFenetre {
            let valeur = glycemieAuTemps(
                t,
                glycemieT0: glycemieT0,
                tempsPic: tempsPicSec,
                valeurPic: valeurPic,
                tempsRetour: tempsRetourSec,
                valeurRetour: valeurRetour
            )
            points.append(PointCgm(secondesDepuisRepas: t, valeur: valeur))
            t += pasEchantillonnage
        }

        // Premier point post-pic dont la valeur est ≤ 180 mg/dL — `nil` si la
        // courbe ne redescend jamais dans la cible (cas du verdict "mauvais").
        let tempsRetourCible: TimeInterval? = points.first {
            $0.secondesDepuisRepas > tempsPicSec && $0.valeur <= 180
        }?.secondesDepuisRepas

        return ReponseGlycemique(
            pointsCgm: points,
            verdict: verdict,
            valeurPic: valeurPic,
            tempsPic: tempsPicSec,
            tempsRetourCible: tempsRetourCible
        )
    }

    /// Modèle 3-phases de la réponse glycémique post-prandiale :
    /// - avant T0 : plateau à `glycemieT0` avec léger bruit sinusoïdal ;
    /// - T0 → pic : rampe ease-in (quadratique) — montée qui s'accélère ;
    /// - pic → retour : ease-out (quadratique inverse) vers `valeurRetour` ;
    /// - après retour : dérive exponentielle vers le baseline pré-repas.
    private static func glycemieAuTemps(
        _ t: TimeInterval,
        glycemieT0: Double,
        tempsPic: TimeInterval,
        valeurPic: Double,
        tempsRetour: TimeInterval,
        valeurRetour: Double
    ) -> Double {
        if t <= 0 {
            // Pré-repas : plateau stable, ondulation organique très douce.
            let bruit = sin(t / 600) * 1.5
            return glycemieT0 + bruit
        }

        if t <= tempsPic {
            // Montée : ease-in quadratique (`progression²`) — la glycémie
            // décolle lentement puis grimpe plus vite en approchant du pic.
            let progression = t / tempsPic
            let eased = progression * progression
            return glycemieT0 + (valeurPic - glycemieT0) * eased
        }

        if t <= tempsRetour {
            // Descente : ease-out quadratique — chute rapide juste après le
            // pic, puis ralentissement à l'approche du palier de retour.
            let progression = (t - tempsPic) / (tempsRetour - tempsPic)
            let eased = 1 - (1 - progression) * (1 - progression)
            return valeurPic + (valeurRetour - valeurPic) * eased
        }

        // Au-delà de `tempsRetour` : décroissance lente vers le baseline.
        // Constante de temps de 2h ⇒ asymptote douce, pas de cassure brutale.
        let dt = t - tempsRetour
        let constanteTemps: TimeInterval = 120 * 60
        let facteur = exp(-dt / constanteTemps)
        return glycemieT0 + (valeurRetour - glycemieT0) * facteur
    }

    // MARK: Génération par points-clés
    //
    // Pour les courbes complexes (double pic, hypo, plateau prolongé), le
    // modèle 3-phases ne suffit pas. On passe par une liste de points-clés
    // (minutes, valeur) et on interpole entre eux avec un smoothstep —
    // l'interpolation `.catmullRom` du Chart adoucit ensuite le rendu final.

    /// Construit une courbe à partir d'une suite de points-clés (instant
    /// en minutes depuis T0, valeur mg/dL). Le pic est détecté automatiquement
    /// à partir de la courbe générée : on prend le maximum sur la fenêtre
    /// post-repas pour positionner le `PointMark` du pic.
    private static func courbeParPoints(
        verdict: VerdictGlycemique,
        pointsCles: [PointCleCourbe]
    ) -> ReponseGlycemique {
        let cles = pointsCles.sorted { $0.minutes < $1.minutes }

        // Échantillonnage régulier : les `tempsPic` détecté tombe forcément
        // sur un point généré (multiple de 300s) — pas de désalignement avec
        // le `PointMark` du pic.
        var points: [PointCgm] = []
        var t = debutFenetre
        while t <= finFenetre {
            let valeur = interpolerCles(t: t, cles: cles)
            points.append(PointCgm(secondesDepuisRepas: t, valeur: valeur))
            t += pasEchantillonnage
        }

        // Détection du pic : maximum strict sur la portion post-repas.
        // Fallback à T0 sur les courbes purement descendantes (`hypoTardive`)
        // pour que l'annotation reste visible quelque part.
        let postRepas = points.filter { $0.secondesDepuisRepas >= 0 }
        let pointPic = postRepas.max(by: { $0.valeur < $1.valeur }) ?? points[0]

        let tempsRetourCible: TimeInterval? = points.first {
            $0.secondesDepuisRepas > pointPic.secondesDepuisRepas && $0.valeur <= 180
        }?.secondesDepuisRepas

        return ReponseGlycemique(
            pointsCgm: points,
            verdict: verdict,
            valeurPic: pointPic.valeur,
            tempsPic: pointPic.secondesDepuisRepas,
            tempsRetourCible: tempsRetourCible
        )
    }

    /// Interpolation smoothstep entre les deux points-clés qui encadrent `t`.
    /// `smoothstep(p) = p²(3 - 2p)` — dérivée nulle aux extrémités, donc
    /// transitions douces aux points-clés (pas de cassure visible).
    private static func interpolerCles(
        t: TimeInterval,
        cles: [(minutes: Double, valeur: Double)]
    ) -> Double {
        let tMin = t / 60
        guard let premier = cles.first, let dernier = cles.last else { return 0 }
        if tMin <= premier.minutes { return premier.valeur }
        if tMin >= dernier.minutes { return dernier.valeur }

        for i in 0..<(cles.count - 1) {
            let a = cles[i]
            let b = cles[i + 1]
            if tMin >= a.minutes && tMin <= b.minutes {
                let progression = (tMin - a.minutes) / (b.minutes - a.minutes)
                let eased = progression * progression * (3 - 2 * progression)
                return a.valeur + (b.valeur - a.valeur) * eased
            }
        }
        return dernier.valeur
    }
}
