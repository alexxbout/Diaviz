//
//  ActivitesSportService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service de la page Sport, branché sur le hub SwiftData. Lit et écrit
/// réellement les `ActiviteSportive` (remplace `ActivitesSportServiceMock`).
///
/// Pattern de démarrage aligné sur `InjectionsService` : la vue crée le
/// service vide puis lui passe le `ModelContext` de l'environnement via
/// `.task`. Le service garde le contexte, recharge `activites` après chaque
/// mutation et l'expose en `@Observable` pour rafraîchir la vue.
///
/// **Un hub, des dérivations** : le hub ne stocke que des faits bruts
/// horodatés (`ActiviteSportive`). La courbe de réponse glycémique exposée
/// par `reponse(pour:)` est une **dérivation calculée à la volée**, jamais
/// persistée. Sa génération est provisoire (l'assembleur réel — corrélation
/// avec les `GlucoseReading` du hub — viendra plus tard) : pour l'instant on
/// réutilise le modèle synthétique 3-phases hérité du mock.
@Observable
@MainActor
final class ActivitesSportService {

    /// Contexte du hub, fourni au démarrage. `nil` tant que `demarrer` n'a
    /// pas été appelé — toutes les opérations sont alors des no-op
    /// (dégradation gracieuse plutôt que crash).
    private var contexte: ModelContext?

    /// Toutes les activités du hub, triées par date de début ascendante.
    /// Rechargé depuis le store après chaque écriture.
    private(set) var activites: [ActiviteSportive] = []

    // MARK: - Démarrage

    /// Branche le service sur le contexte du hub et charge les données.
    /// Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    // MARK: - Lecture par jour

    /// Activités d'un jour donné, triées par heure ascendante.
    func activitesDuJour(_ jour: Date) -> [ActiviteSportive] {
        let cal = Calendar.current
        return activites
            .filter { cal.isDate($0.dateDebut, inSameDayAs: jour) }
            .sorted { $0.dateDebut < $1.dateDebut }
    }

    /// Nombre d'activités enregistrées aujourd'hui — alimente le sous-titre
    /// de la carte « Activités sportives » du journal.
    var nombreActivitesAujourdhui: Int {
        activitesDuJour(Date()).count
    }

    // MARK: - Dérivation (réponse glycémique)

    /// Réponse glycémique associée à une activité.
    ///
    /// **Provisoire (dérivation, assembleur à venir)** — calculée à la volée
    /// à chaque accès, jamais persistée (« un hub, des dérivations »). La
    /// génération est déterministe (pas de `random`), donc cohérente d'un
    /// appel à l'autre.
    ///
    /// Pour l'instant : modèle synthétique 3-phases hérité du mock.
    /// L'assembleur réel (corrélation avec les glycémies du hub sur la fenêtre
    /// de l'activité) remplacera cette génération sans changer la signature.
    func reponse(pour activite: ActiviteSportive) -> ReponseGlycemiqueSport? {
        Self.genererReponse(pour: activite)
    }

    // MARK: - Écriture

    /// Enregistre une activité (création ou édition). **Upsert par `id`** :
    /// si une activité de même `id` existe déjà (cas édition — la sheet
    /// réémet un objet détaché avec l'`id` d'origine), elle est remplacée
    /// plutôt que doublonnée.
    func enregistrer(_ activite: ActiviteSportive) {
        guard let contexte else { return }
        // IOB actif juste avant le début de la séance — figé à la saisie si non
        // renseigné (dérivé du hub). On ne recalcule pas en édition.
        if activite.iobAuDebut == nil {
            let iob = IOBService.iobDuHub(a: activite.dateDebut, contexte: contexte)
            activite.iobAuDebut = iob > 0.05 ? iob : nil
        }
        let cible = activite.id
        let descripteur = FetchDescriptor<ActiviteSportive>(predicate: #Predicate { $0.id == cible })
        if let existant = try? contexte.fetch(descripteur).first, existant !== activite {
            contexte.delete(existant)
        }
        contexte.insert(activite)
        try? contexte.save()
        recharger()
    }

    /// Supprime une activité du hub.
    func supprimer(_ activite: ActiviteSportive) {
        guard let contexte else { return }
        contexte.delete(activite)
        try? contexte.save()
        recharger()
    }

    // MARK: - Privé

    private func recharger() {
        guard let contexte else { return }
        let descripteur = FetchDescriptor<ActiviteSportive>(sortBy: [SortDescriptor(\.dateDebut)])
        activites = (try? contexte.fetch(descripteur)) ?? []
    }
}

// MARK: - Génération de courbe glycémique (dérivation provisoire)
//
// Modèle synthétique 3-phases hérité de l'ancien `ActivitesSportServiceMock`.
// Conservé tel quel comme dérivation calculée tant que l'assembleur réel
// (corrélation avec les `GlucoseReading` du hub) n'est pas branché. Statique
// et pur — pas d'état, donc réutilisable depuis les previews.

extension ActivitesSportService {

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
    /// type × intensité × IOB. Cardio = descente, muscu = stable à
    /// légère montée puis descente, yoga = quasi stable.
    ///
    /// Le facteur IOB amplifie la chute : commencer une séance avec
    /// 2u d'insuline encore active double quasiment l'amplitude de
    /// descente — c'est physiologiquement vrai (l'IOB continue
    /// d'agir pendant l'effort, pendant que les muscles consomment
    /// déjà du glucose). Sans ce facteur, le générateur ne produit
    /// jamais d'hypoglycémie sur les mocks réalistes — donc le
    /// marqueur d'hypo des graphiques ne se déclenche jamais à
    /// l'usage.
    ///
    /// Ces valeurs sont une approximation de patterns observés ; le
    /// vrai modèle viendra de la couche ML quand l'assembleur sera
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

        // Facteur IOB : 1u IOB ajoute ~20% d'amplitude. Capé à +60%
        // pour rester sous une chute physiologiquement plausible —
        // au-delà la formule produirait des hypos sévères (< 30 mg/dL)
        // qu'on ne veut pas avoir dans le mock par défaut.
        let facteurIOB: Double = {
            guard let iob = activite.iobAuDebut, iob > 0 else { return 1.0 }
            return 1.0 + min(0.6, iob * 0.25)
        }()

        return deltaBase * amplitudeIntensite * facteurIOB
    }

    /// Dérive **après** la session, sur les 30min post-effort. Pour la
    /// musculation intense on simule un léger rebond hyperglycémique
    /// (réaction adrénergique typique). Pour le cardio, la glycémie
    /// peut continuer à baisser (effet retardé).
    private static func deltaApres(pour activite: ActiviteSportive) -> Double {
        switch (activite.type.categorie, activite.intensite) {
        case (.cardio, .intense):      return -10  // chute prolongée
        case (.cardio, _):             return -3   // léger biais descendant
        case (.musculation, .intense): return 15   // rebond adrénergique
        case (.musculation, _):        return 5
        case (.autre, _):              return 0
        }
    }
}

#if DEBUG
extension ActivitesSportService {

    /// Container in-memory peuplé pour les `#Preview` — remplace l'ancien
    /// jeu mock. Hors `DEBUG`, l'app démarre sur un hub vide (dégradation
    /// gracieuse).
    @MainActor
    static var conteneurApercu: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: ActiviteSportive.self, configurations: config)
        for activite in echantillonsApercu() {
            container.mainContext.insert(activite)
        }
        return container
    }

    /// Service prêt à l'emploi pour les previews qui ont besoin de l'API
    /// d'instance (`activites`, `activitesDuJour`, `reponse(pour:)`) sans
    /// passer par une vue. Démarré sur le `conteneurApercu` peuplé.
    @MainActor
    static func apercu() -> ActivitesSportService {
        let service = ActivitesSportService()
        service.demarrer(contexte: conteneurApercu.mainContext)
        return service
    }

    /// Jeu d'activités de démonstration cohérent sur 7 jours. Uniquement
    /// pour previews / captures.
    ///
    /// - aujourd'hui : 1 course du matin (07:15) + 1 yoga (12:00) + 1 course
    ///   intense fin d'aprem (cas hypo pédagogique)
    /// - 6 jours précédents : un mix course/vélo/musculation/marche pour
    ///   permettre de naviguer dans le graphe et voir des cas variés.
    static func echantillonsApercu() -> [ActiviteSportive] {
        let cal = Calendar.current

        func dateA(_ h: Int, _ m: Int = 0, ilYA jours: Int = 0) -> Date {
            let jourBase = cal.date(byAdding: .day, value: -jours, to: Date()) ?? Date()
            return cal.date(bySettingHour: h, minute: m, second: 0, of: jourBase) ?? Date()
        }

        // IOB calibré pour exercer les 3 niveaux du badge sur la page
        // détail (modéré 0–1u, élevé 1–2u, très élevé > 2u). On garde
        // une cohérence narrative : course du matin avec IOB modéré
        // (petit-déj récent), vélo de fin d'aprem avec IOB élevé
        // (déjeuner pas si loin), yoga sans IOB (mid-day, à distance
        // des bolus), muscu avec IOB faible.
        return [
            // MARK: Aujourd'hui — 1 course matin + 1 yoga midi
            ActiviteSportive(
                type: .course,
                dateDebut: dateA(7, 15),
                dureeMinutes: 45,
                intensite: .moderee,
                glucidesPreSport: 15,
                note: "Footing matinal au parc",
                iobAuDebut: 1.2
            ),
            ActiviteSportive(
                type: .yoga,
                dateDebut: dateA(12, 0),
                dureeMinutes: 30,
                intensite: .faible,
                glucidesPreSport: nil,
                note: nil,
                iobAuDebut: nil
            ),
            // MARK: Aujourd'hui — course intense fin d'aprem avec IOB
            // élevé. Cas pédagogique : c'est le scénario qui produit
            // une hypoglycémie en fin d'effort (combinaison effort
            // soutenu + IOB important + pas de glucides pré-sport)
            // et qui exerce donc le marqueur rouge d'hypo sur les
            // graphiques. Sans cette ligne, aucune des activités
            // mockées ne descendrait sous 70 mg/dL.
            ActiviteSportive(
                type: .course,
                dateDebut: dateA(17, 0),
                dureeMinutes: 50,
                intensite: .intense,
                glucidesPreSport: nil,
                note: "Sortie longue sans collation pré-sport",
                iobAuDebut: 2.5
            ),

            // MARK: Hier — vélo de fin d'après-midi
            ActiviteSportive(
                type: .velo,
                dateDebut: dateA(17, 30, ilYA: 1),
                dureeMinutes: 60,
                intensite: .moderee,
                glucidesPreSport: 20,
                iobAuDebut: 2.5
            ),

            // MARK: J-2 — séance de muscu en fin de journée
            ActiviteSportive(
                type: .musculation,
                dateDebut: dateA(18, 45, ilYA: 2),
                dureeMinutes: 50,
                intensite: .intense,
                glucidesPreSport: nil,
                iobAuDebut: 0.5
            ),

            // MARK: J-3 — marche longue en milieu de journée
            ActiviteSportive(
                type: .marche,
                dateDebut: dateA(11, 30, ilYA: 3),
                dureeMinutes: 75,
                intensite: .faible,
                glucidesPreSport: nil,
                iobAuDebut: nil
            ),

            // MARK: J-4 — course intense + yoga en récupération
            ActiviteSportive(
                type: .course,
                dateDebut: dateA(7, 30, ilYA: 4),
                dureeMinutes: 30,
                intensite: .intense,
                glucidesPreSport: 10,
                iobAuDebut: 0.8
            ),
            ActiviteSportive(
                type: .yoga,
                dateDebut: dateA(19, 0, ilYA: 4),
                dureeMinutes: 45,
                intensite: .faible,
                iobAuDebut: nil
            ),

            // MARK: J-5 — sport collectif (foot)
            ActiviteSportive(
                type: .sportCollectif,
                dateDebut: dateA(20, 0, ilYA: 5),
                dureeMinutes: 90,
                intensite: .intense,
                glucidesPreSport: 30,
                note: "Match du jeudi",
                iobAuDebut: 1.7
            ),

            // MARK: J-6 — natation
            ActiviteSportive(
                type: .natation,
                dateDebut: dateA(8, 0, ilYA: 6),
                dureeMinutes: 40,
                intensite: .moderee,
                glucidesPreSport: 15,
                iobAuDebut: 1.0
            ),
        ]
    }
}
#endif
