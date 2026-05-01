//
//  ActivitesSportServiceMock.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation
import Observation

/// Service mocké pour la page Sport.
///
/// Expose un jeu d'activités sportives cohérent sur 7 jours :
/// - aujourd'hui : 1 course du matin (07:15) + 1 yoga (12:00)
/// - 6 jours précédents : un mix course/vélo/musculation/marche pour
///   permettre de naviguer dans le graphe et voir des cas variés.
///
/// Pour chaque activité, le service génère une `ReponseGlycemiqueSport`
/// synthétique via `genererReponse(...)` — ~20 points sur la fenêtre
/// `[-30min, dureeSession + 30min]`, avec une dynamique réaliste qui
/// dépend du type et de l'intensité.
///
/// Branchera l'API NestJS / Prisma plus tard ; l'API publique
/// (`activites`, `reponse(pour:)`) reste stable.
@Observable
@MainActor
final class ActivitesSportServiceMock {

    static let shared = ActivitesSportServiceMock()

    /// Toutes les activités connues, multi-jours, non triées.
    private(set) var activites: [ActiviteSportive]

    /// Réponses glycémiques pré-calculées, indexées par `id` d'activité.
    /// On les calcule une fois en `init` plutôt qu'à chaque accès — la
    /// génération est déterministe (pas de `random`), donc cohérente
    /// d'une row à l'autre.
    private var reponses: [UUID: ReponseGlycemiqueSport]

    private init() {
        let donnees = Self.donneesInitiales()
        self.activites = donnees
        self.reponses = Dictionary(
            uniqueKeysWithValues: donnees.map { activite in
                (activite.id, Self.genererReponse(pour: activite))
            }
        )
    }

    // MARK: - Lecture

    /// Activités d'un jour donné, triées par heure ascendante.
    func activitesDuJour(_ jour: Date) -> [ActiviteSportive] {
        let cal = Calendar.current
        return activites
            .filter { cal.isDate($0.dateDebut, inSameDayAs: jour) }
            .sorted { $0.dateDebut < $1.dateDebut }
    }

    /// Réponse glycémique associée à une activité, si pré-calculée.
    /// `nil` est sémantiquement « données manquantes » — la mini-courbe
    /// affichera l'icône `exclamationmark.triangle` dans ce cas.
    func reponse(pour activite: ActiviteSportive) -> ReponseGlycemiqueSport? {
        reponses[activite.id]
    }

    // MARK: - Écriture (mock — uniquement local, pas de persistance)

    func ajouter(_ activite: ActiviteSportive) {
        activites.append(activite)
        reponses[activite.id] = Self.genererReponse(pour: activite)
    }

    func supprimer(_ activite: ActiviteSportive) {
        activites.removeAll { $0.id == activite.id }
        reponses.removeValue(forKey: activite.id)
    }

    // MARK: - Données mockées

    private static func donneesInitiales() -> [ActiviteSportive] {
        let cal = Calendar.current

        func dateA(_ h: Int, _ m: Int = 0, ilYA jours: Int = 0) -> Date {
            let jourBase = cal.date(byAdding: .day, value: -jours, to: Date()) ?? Date()
            return cal.date(bySettingHour: h, minute: m, second: 0, of: jourBase) ?? Date()
        }

        return [
            // MARK: Aujourd'hui — 1 course matin + 1 yoga midi
            ActiviteSportive(
                type: .course,
                dateDebut: dateA(7, 15),
                dureeMinutes: 45,
                intensite: .moderee,
                glucidesPreSport: 15,
                note: "Footing matinal au parc"
            ),
            ActiviteSportive(
                type: .yoga,
                dateDebut: dateA(12, 0),
                dureeMinutes: 30,
                intensite: .faible,
                glucidesPreSport: nil,
                note: nil
            ),

            // MARK: Hier — vélo de fin d'après-midi
            ActiviteSportive(
                type: .velo,
                dateDebut: dateA(17, 30, ilYA: 1),
                dureeMinutes: 60,
                intensite: .moderee,
                glucidesPreSport: 20
            ),

            // MARK: J-2 — séance de muscu en fin de journée
            ActiviteSportive(
                type: .musculation,
                dateDebut: dateA(18, 45, ilYA: 2),
                dureeMinutes: 50,
                intensite: .intense,
                glucidesPreSport: nil
            ),

            // MARK: J-3 — marche longue en milieu de journée
            ActiviteSportive(
                type: .marche,
                dateDebut: dateA(11, 30, ilYA: 3),
                dureeMinutes: 75,
                intensite: .faible,
                glucidesPreSport: nil
            ),

            // MARK: J-4 — course intense + yoga en récupération
            ActiviteSportive(
                type: .course,
                dateDebut: dateA(7, 30, ilYA: 4),
                dureeMinutes: 30,
                intensite: .intense,
                glucidesPreSport: 10
            ),
            ActiviteSportive(
                type: .yoga,
                dateDebut: dateA(19, 0, ilYA: 4),
                dureeMinutes: 45,
                intensite: .faible
            ),

            // MARK: J-5 — sport collectif (foot)
            ActiviteSportive(
                type: .sportCollectif,
                dateDebut: dateA(20, 0, ilYA: 5),
                dureeMinutes: 90,
                intensite: .intense,
                glucidesPreSport: 30,
                note: "Match du jeudi"
            ),

            // MARK: J-6 — natation
            ActiviteSportive(
                type: .natation,
                dateDebut: dateA(8, 0, ilYA: 6),
                dureeMinutes: 40,
                intensite: .moderee,
                glucidesPreSport: 15
            ),
        ]
    }

    // MARK: - Génération de courbe glycémique

    /// Pas d'échantillonnage en secondes (5 minutes — résolution typique
    /// du CGM Dexcom ONE+).
    private static let pasEchantillonnage: TimeInterval = 5 * 60

    /// Marge avant et après la session sur la fenêtre observée.
    private static let margeFenetre: TimeInterval = 30 * 60

    /// Construit une courbe synthétique cohérente avec le type et
    /// l'intensité de l'activité.
    ///
    /// Modèle simplifié — 3 phases :
    /// - **Avant** (-30min → 0) : plateau stable ~110 mg/dL
    /// - **Pendant** (0 → durée) : variation linéaire de `deltaSouhaite`
    ///   selon le type (cardio → descente, muscu → légère montée puis
    ///   descente, yoga → quasi stable)
    /// - **Après** (durée → +30min) : poursuite de la dérive ou rebond
    ///   léger pour la muscu intense.
    ///
    /// Les valeurs sont calibrées pour qu'au moins un cas par catégorie
    /// produise un verdict visuellement distinct (vert stable / bleu
    /// modéré / orange descente importante / rouge hypo).
    static func genererReponse(pour activite: ActiviteSportive) -> ReponseGlycemiqueSport {
        let glycemieDebut = baselineDebut(pour: activite)
        let dureeSec = TimeInterval(activite.dureeMinutes * 60)
        let deltaPendantSession = deltaPendant(pour: activite)
        let deltaApresSession = deltaApres(pour: activite)

        var points: [PointCgmSport] = []
        var t: TimeInterval = -margeFenetre
        let finFenetre = dureeSec + margeFenetre

        while t <= finFenetre {
            let valeur = glycemieAuTemps(
                t,
                glycemieDebut: glycemieDebut,
                dureeSession: dureeSec,
                deltaPendant: deltaPendantSession,
                deltaApres: deltaApresSession
            )
            points.append(PointCgmSport(secondesDepuisDebut: t, valeur: valeur))
            t += pasEchantillonnage
        }

        // Récupération précise des points début (t=0) et fin (t=durée) :
        // ils tombent pile sur des multiples de 300s pour les durées
        // mockées (multiples de 5min), mais on prend le plus proche au
        // cas où l'utilisateur saisirait une durée arbitraire.
        let pointDebut = points.min(by: { abs($0.secondesDepuisDebut) < abs($1.secondesDepuisDebut) })
        let pointFin = points.min(by: { abs($0.secondesDepuisDebut - dureeSec) < abs($1.secondesDepuisDebut - dureeSec) })
        let valeurDebut = pointDebut?.valeur ?? glycemieDebut
        let valeurFin = pointFin?.valeur ?? glycemieDebut

        return ReponseGlycemiqueSport(
            pointsCgm: points,
            glycemieDebut: valeurDebut,
            glycemieFin: valeurFin,
            deltaMgDl: valeurFin - valeurDebut
        )
    }

    /// Glycémie au temps `t` selon le modèle 3-phases. `t=0` est le
    /// début de la session ; `t = dureeSession` est la fin.
    private static func glycemieAuTemps(
        _ t: TimeInterval,
        glycemieDebut: Double,
        dureeSession: TimeInterval,
        deltaPendant: Double,
        deltaApres: Double
    ) -> Double {
        if t <= 0 {
            // Plateau pré-session — léger bruit sinusoïdal pour rendu
            // organique (la glycémie n'est jamais parfaitement plate).
            return glycemieDebut + sin(t / 600) * 1.5
        }

        if t <= dureeSession {
            // Pendant l'effort : interpolation linéaire avec un léger
            // ease-in (la chute glycémique met quelques minutes à
            // s'amorcer le temps que les muscles épuisent leur
            // glycogène local).
            let progression = t / dureeSession
            let eased = progression * progression * (3 - 2 * progression)
            return glycemieDebut + deltaPendant * eased
        }

        // Après la session : poursuite douce ou rebond selon `deltaApres`.
        // Dérive linéaire sur la fenêtre [+0, +30min] depuis la valeur
        // de fin de session.
        let dt = t - dureeSession
        let progression = min(dt / margeFenetre, 1.0)
        let valeurFin = glycemieDebut + deltaPendant
        return valeurFin + deltaApres * progression
    }

    // MARK: - Paramètres dépendant du type/intensité

    /// Glycémie de départ — légèrement plus élevée si glucides pré-sport
    /// (effet rapide pris en compte dans la baseline observée).
    private static func baselineDebut(pour activite: ActiviteSportive) -> Double {
        let base: Double = 110
        guard let glucides = activite.glucidesPreSport else { return base }
        // 15g de glucides rapides ≈ +20 mg/dL en 20–30min, capé à +40.
        return base + min(40, glucides * 1.3)
    }

    /// Variation glycémique attendue **pendant** la session, selon
    /// type × intensité. Cardio = descente, muscu = stable à légère
    /// montée puis descente, yoga = quasi stable.
    ///
    /// Ces valeurs sont une approximation de patterns observés ; le
    /// vrai modèle viendra de la couche ML quand le backend sera
    /// branché.
    private static func deltaPendant(pour activite: ActiviteSportive) -> Double {
        let amplitudeIntensite: Double = {
            switch activite.intensite {
            case .faible:    return 0.6
            case .moderee:   return 1.0
            case .intense:   return 1.5
            }
        }()

        let deltaBase: Double = {
            switch activite.type.categorie {
            case .cardio:        return -25  // chute typique en cardio modéré
            case .musculation:   return -10  // moins prononcée, parfois +
            case .autre:         return -5   // yoga/marche douce — quasi stable
            }
        }()

        return deltaBase * amplitudeIntensite
    }

    /// Dérive **après** la session, sur les 30min post-effort. Pour la
    /// musculation intense on simule un léger rebond hyperglycémique
    /// (réaction adrénergique typique). Pour le cardio, la glycémie
    /// peut continuer à baisser (effet retardé).
    private static func deltaApres(pour activite: ActiviteSportive) -> Double {
        switch (activite.type.categorie, activite.intensite) {
        case (.cardio, .intense):     return -10  // chute prolongée
        case (.cardio, _):            return -3   // léger biais descendant
        case (.musculation, .intense): return 15  // rebond adrénergique
        case (.musculation, _):       return 5
        case (.autre, _):             return 0
        }
    }
}
