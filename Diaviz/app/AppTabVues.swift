//
//  AppTabView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import CoreData
import HealthKit
import SwiftData
import SwiftUI

/// Vue racine — `TabView` portant les onglets de l'app. L'onglet
/// Recherche est retiré côté navigation le temps qu'il soit géré sur une
/// autre branche — `RecercheVue` reste dans le repo, juste plus montée ici.
///
/// Branchée sur `HealthKitImportService.shared` pour afficher un
/// **badge** sur l'onglet Journal reflétant en temps réel le nombre de
/// workouts Apple Santé en attente d'import. L'import lui-même se fait
/// depuis la page Sport (sheet déclenchée par bouton dédié) — pas
/// d'ouverture automatique au lancement.
struct AppTabVues: View {

    /// Onglet actif — sert uniquement à déclencher le retour haptique au
    /// changement d'onglet (`.sensoryFeedback` a besoin d'une valeur
    /// observable à surveiller). Aucun contrôle programmatique de la
    /// navigation n'en dépend.
    @State private var ongletActif: String = "accueil"

    /// Service hub des repas — source de vérité de l'onglet Journal. Démarré
    /// au boot via `.task` (contexte du hub), il fournit les sections du jour
    /// et le compteur de repas. En prod le hub est vide au départ → état vide
    /// honnête ; les previews injectent un container peuplé via
    /// `.modelContainer(RepasService.conteneurApercu)`.
    @State private var repasService = RepasService()

    /// Service d'import — pris depuis le singleton plutôt qu'instancié
    /// localement, parce qu'il porte de l'état partagé avec le badge
    /// de la `JournalVue` et le bouton d'import de la `SportVue`.
    @State private var importService = HealthKitImportService.shared

    /// Service de profil — partagé entre l'accueil (avatar) et la
    /// sheet `ProfilVue`. Injecté via `.environment` ; les vues le
    /// récupèrent par `@Environment(ProfilService.self)`.
    @State private var profilService = ProfilService.shared

    /// Service HealthKit — autorisation, synchro incrémentale et surveillance
    /// background des glycémies vers le hub.
    @State private var healthKit = HealthKitCGMService()

    /// Service de l'analyse basale (B1) — instance **unique** partagée entre
    /// l'onglet Analyses (détail), l'accueil (insight « nouvelle tendance »)
    /// et le badge de cet onglet. Doit être la même instance partout (pas un
    /// `@State` privé par vue) pour que « marquer comme vu » depuis le détail
    /// efface le badge vu par les deux autres écrans.
    @State private var analyseBasaleService = AnalyseBasaleService()

    /// Services des analyses B2/B3 — dépendent de `analyseBasaleService` pour
    /// l'ancrage de nuit (lente, glycémie au coucher). Mêmes règles d'instance
    /// unique partagée que B1.
    @State private var analyseEndormissementService = AnalyseEndormissementService()
    @State private var analyseCorrectionsService = AnalyseCorrectionsService()

    /// Bilan des corrections toutes heures — indépendant de B1/B3, aucun
    /// ancrage de nuit requis, boot autonome.
    @State private var bilanCorrectionsService = BilanCorrectionsService()

    /// Service du mining R1 (ratio observé) — cache mémoire recalculé sur
    /// mutation du hub, pas à chaque frappe de saisie. Lit `repasService.repas`
    /// directement, aucun fetch SwiftData séparé.
    @State private var analyseRatioService = AnalyseRatioService()

    /// Service de la tendance hebdomadaire de glucides — même pattern que
    /// `analyseRatioService` (cache mémoire, recalculé sur mutation du hub).
    @State private var glucidesHebdoService = GlucidesHebdoService()

    /// File des confirmations éphémères (repas, insuline, sport, resucrage) —
    /// singleton, les services du hub y écrivent sans passer par une vue.
    @State private var toastsService = ToastsService.shared

    /// Service de séance sportive chronométrée « en direct » (singleton) —
    /// l'écran plein écran de la séance en cours est présenté **ici**, à la
    /// racine toujours montée, et non depuis `SportVue` (qui est poussée via
    /// `NavigationLink` et se désalloue dès qu'on la quitte — c'est ce qui
    /// faisait disparaître le chrono jusqu'au retour manuel sur cette page).
    @State private var sessionService = SessionSportService.shared

    /// Instance dédiée à l'enregistrement du brouillon de fin de séance —
    /// même pattern que les instances déjà indépendantes de `JournalVue` et
    /// `SportVue` (`ActivitesSportService` n'a pas de singleton, chaque
    /// appelant garde son propre cache ; l'écriture passe par le hub donc
    /// aucune donnée n'est perdue entre instances).
    @State private var sessionActivitesService = ActivitesSportService()

    /// Brouillon d'activité à enregistrer après l'arrêt d'une séance
    /// chronométrée — pilote la sheet d'enregistrement pré-remplie.
    @State private var brouillonSession: BrouillonSession?

    /// Contexte SwiftData du hub (pour récupérer le `ModelContainer`).
    @Environment(\.modelContext) private var modelContext

    /// Phase de scène — au retour au premier plan on resynchronise l'état de
    /// séance (les boutons de la Dynamic Island mutent hors de l'app).
    @Environment(\.scenePhase) private var scenePhase

    /// Jour pour lequel on souhaite pousser `DetailScoreVue` dans l'onglet
    /// Accueil — écrit au tap sur la carte score, observé par `AccueilVue`
    /// via binding qui déclenche la push via `navigationDestination(item:)`.
    @State private var jourDetailScore: Date?

    /// États possibles de la séquence de démarrage, résolus une fois dans
    /// `.task` (impossible de la résoudre plus tôt : ni le `ModelContext`
    /// ni la détection CloudKit ne sont disponibles à l'initialisation de
    /// la vue). Une revisite volontaire de l'onboarding depuis le profil
    /// passe par son propre `fullScreenCover` local dans `ProfilVue`,
    /// indépendant de celui-ci.
    private enum EtatDemarrage {
        /// En cours de résolution — rien à afficher par-dessus le `TabView`
        /// (l'app est de toute façon vide/normale à ce stade).
        case verification
        /// Aucune donnée trouvée (ni locale, ni sur iCloud après attente) :
        /// onboarding classique.
        case onboarding
        /// Données trouvées (hub non vide ou profil valide) mais alors que
        /// le profil courant n'était pas encore configuré sur cet appareil
        /// — propose de les récupérer ou de repartir de zéro.
        case choixRestauration
        /// Rien à afficher, l'app se lance normalement.
        case pret
    }

    @State private var etatDemarrage: EtatDemarrage = .verification

    /// Binding vers la séance en cours pour piloter le `fullScreenCover`.
    /// `set` : seule la mise à `nil` (dismiss système) est relayée en abandon
    /// — le service reste la source de vérité pour les transitions internes.
    private var bindingSession: Binding<SessionSportiveEnCours?> {
        Binding(
            get: { sessionService.session },
            set: { nouvelle in if nouvelle == nil { sessionService.annuler() } }
        )
    }

    var body: some View {
        TabView(selection: $ongletActif) {
            Tab("Accueil", systemImage: "house", value: "accueil") {
                AccueilVue(jourDetailScore: $jourDetailScore)
            }

            Tab("Journal", systemImage: "long.text.page.and.pencil", value: "journal") {
                JournalVue()
            }
            .badge(importService.nombreEnAttente)

            Tab("Analyses", systemImage: "chart.bar.fill", value: "analyses") {
                AnalysesVue()
            }
            // `nil`, pas `""` : une chaîne vide non-nil affichait quand même
            // une pastille (vide) en permanence, quel que soit
            // `estNouvelleTendance`.
            .badge(analyseBasaleService.estNouvelleTendance ? Text("•") : nil)
        }
        // Confirmations d'enregistrement — couche de chrome au-dessus des
        // onglets, donc en overlay de la `TabView` et non dans une page :
        // une pilule doit survivre au changement d'onglet et à la fermeture
        // de la sheet qui l'a déclenchée.
        .overlay(alignment: .top) {
            PileToasts()
        }
        .environment(toastsService)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Léger retour haptique au changement d'onglet — cohérent avec les
        // autres `.sensoryFeedback` déjà présents (site d'injection, timeline
        // basale, bouton valider repas).
        .sensoryFeedback(.selection, trigger: ongletActif)
        // Injection de la racine — toutes les vues filles consomment le
        // même service via `@Environment(HealthKitImportService.self)`,
        // ce qui rend les previews capable de fournir un mock isolé.
        .environment(importService)
        .environment(profilService)
        .environment(repasService)
        .environment(analyseBasaleService)
        .environment(analyseEndormissementService)
        .environment(analyseCorrectionsService)
        .environment(bilanCorrectionsService)
        .environment(analyseRatioService)
        .environment(glucidesHebdoService)
        .fullScreenCover(isPresented: Binding(
            get: { etatDemarrage == .onboarding || etatDemarrage == .choixRestauration },
            set: { presente in
                guard !presente else { return }
                // L'utilisateur vient de terminer l'onboarding : la question
                // du premier lancement est close. Sans ça, l'app ayant entre
                // temps exporté vers iCloud, la zone existerait au prochain
                // démarrage et l'écran de restauration lui serait reproposé
                // alors qu'il vient tout juste de se configurer.
                marquerDemarrageResolu()
                etatDemarrage = .pret
            }
        )) {
            // Réinjection explicite : cette cover peut s'ouvrir dès le tout
            // premier rendu — avant que l'héritage normal de
            // `.environment(profilService)` ci-dessus soit garanti pour ce
            // premier affichage. Sans ça, `EtapeIdentiteOnboarding` etc.
            // plantent au lancement (« No Observable object of type
            // ProfilService found »).
            Group {
                switch etatDemarrage {
                case .choixRestauration:
                    ChoixRestaurationICloudVue(
                        onRecuperer: {
                            marquerDemarrageResolu()
                            etatDemarrage = .pret
                        },
                        onRepartirDeZero: {
                            marquerDemarrageResolu()
                            etatDemarrage = .onboarding
                        }
                    )
                default:
                    OnboardingVue()
                }
            }
            .environment(profilService)
        }
        // Écran plein écran de la séance sportive en cours — présenté depuis
        // la racine (toujours montée) pour ne pas disparaître au changement
        // d'onglet ou en remontant la stack de navigation du Journal.
        .fullScreenCover(item: bindingSession) { session in
            SeanceEnCoursVue(
                session: session,
                onTerminer: { brouillon in brouillonSession = BrouillonSession(activite: brouillon) },
                onAnnuler: { sessionService.annuler() }
            )
        }
        .sheet(item: $brouillonSession) { brouillon in
            SheetNouvelleActivite(
                preremplissage: brouillon.activite,
                onValider: { sessionActivitesService.enregistrer($0) }
            )
        }
        // Réconciliation avec la Dynamic Island (pause/reprise/fin mutées
        // hors de l'app par un `LiveActivityIntent`) — au retour au premier
        // plan, peu importe l'onglet actif.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if let brouillon = sessionService.reconcilier() {
                brouillonSession = BrouillonSession(activite: brouillon)
            }
        }
        .task {
            await resoudreEtatDemarrage()
            demarrerServicesPreferences()
            sessionActivitesService.demarrer(contexte: modelContext)
            repasService.demarrer(contexte: modelContext)
            analyseRatioService.recalculer(depuis: repasService.repas, contexte: modelContext)
            glucidesHebdoService.recalculer(depuis: repasService.repas)
            // B1 doit être démarré (et son `analyse` à jour) avant B2/B3, qui
            // lisent `analyseBasaleService.analyse` — d'où l'attente séquentielle.
            await analyseBasaleService.demarrer(contexte: modelContext)
            async let endo: Void = analyseEndormissementService.demarrer(contexte: modelContext, basale: analyseBasaleService)
            async let corr: Void = analyseCorrectionsService.demarrer(contexte: modelContext, basale: analyseBasaleService)
            // Boot indépendant : aucun ancrage de nuit requis.
            async let bilanCorr: Void = bilanCorrectionsService.demarrer(contexte: modelContext)
            _ = await (endo, corr, bilanCorr)
            // `HealthKitCGMService` et `HealthKitImportService` demandent
            // chacun leur propre type (glycémies / workouts) via leur
            // propre `HKHealthStore` — sans ce préflight groupé, chaque
            // `demanderAcces()` déclenche sa propre sheet système, donc
            // deux sheets HealthKit à la suite au premier lancement. Une
            // fois un type tranché (accordé ou refusé), HealthKit ne
            // redemande jamais — les deux `demanderAcces()` ci-dessous
            // retombent donc à un no-op silencieux après ce préflight.
            // Le sommeil n'est **pas** inclus ici volontairement : sa
            // sheet d'autorisation Santé ne doit apparaître qu'à
            // l'activation explicite du réglage overlay (voir
            // `SectionAnalyseCoucherReglages`), jamais au boot.
            _ = try? await HKHealthStore().requestAuthorization(
                toShare: [],
                read: [HKQuantityType(.bloodGlucose), HKObjectType.workoutType()]
            )
            await healthKit.demanderAcces()
            await healthKit.synchroniser(container: modelContext.container)
            healthKit.demarrerSurveillance(container: modelContext.container)
            await importService.demanderAcces()
            await importService.rafraichir()
            // Le CGM vient d'être synchronisé : recalcule les réponses
            // glycémiques des repas (au démarrage elles étaient toutes en
            // attente, faute de glycémies encore chargées).
            repasService.rafraichirAnalyses()
            // Les verdicts persistés viennent de changer (repas passés de
            // enAttente à disponible) : remine le ratio observé.
            analyseRatioService.recalculer(depuis: repasService.repas, contexte: modelContext)
            glucidesHebdoService.recalculer(depuis: repasService.repas)
        }
        // `.task` séparé : tourne pour toute la durée de vie de l'app (vue
        // racine), indépendamment de la séquence de démarrage ci-dessus.
        // Suit l'activité CloudKit (affichée dans la page Données) et
        // rattrape à chaque réception les données arrivées d'un autre
        // appareil, que les services tiennent en mémoire.
        .task {
            await SyncICloudService.shared.observer {
                profilService.rafraichirDepuisCloudKit()
                rechargerServicesPreferences()
            }
        }
    }

    /// Vrai une fois que la détection iCloud a déjà tranché une fois sur cet
    /// appareil (accès direct à l'app, onboarding terminé, ou choix
    /// restauration/repartir de zéro fait). Sans ce flag, la détection (avec
    /// son attente CloudKit) se rejouerait à **chaque** lancement tant que le
    /// profil reste incomplet — recommandation Apple DTS explicite (cf. plan)
    /// pour éviter exactement ce problème.
    private static let cleDemarrageResolu = "demarragePremierLancementResolu"

    // MARK: - Séquence de démarrage (onboarding vs restauration iCloud)

    /// Décide de l'état de démarrage. Fait la détection AVANT d'appeler
    /// `profilService.demarrer(contexte:)` : sur un compte iCloud avec des
    /// données pas encore importées, démarrer le service tout de suite
    /// créerait une ligne profil locale vide, qui coexisterait ensuite avec
    /// la ligne distante une fois importée — exactement le cas « plusieurs
    /// lignes » que `ProfilService.demarrer` sait gérer, mais qu'il vaut
    /// mieux éviter de provoquer inutilement à chaque lancement.
    private func resoudreEtatDemarrage() async {
        profilService.demarrer(contexte: modelContext)

        // Question déjà tranchée sur cet appareil : l'app démarre
        // normalement, l'écran de restauration ne revient jamais.
        if UserDefaults.standard.bool(forKey: Self.cleDemarrageResolu) {
            etatDemarrage = profilService.profil.estValide ? .pret : .onboarding
            return
        }

        // Des données sont déjà là (relance rapide après une installation
        // dont la synchronisation avait commencé) : la question se pose.
        if detecterDonneesExistantes(modelContext) {
            etatDemarrage = .choixRestauration
            return
        }

        // Sinon, demander directement au serveur. On n'attend surtout pas un
        // événement d'import : le premier arrive souvent vide, à la mise en
        // place du store, et conclure dessus faisait manquer des données qui
        // arrivaient une poignée de secondes plus tard.
        switch await SyncICloudService.interrogerDonneesICloud() {
        case .presentes:
            // Pas de `marquerDemarrageResolu()` ici : la décision appartient
            // encore à l'utilisateur. Le poser maintenant ferait disparaître
            // l'écran pour de bon si l'app était tuée avant qu'il ait choisi
            // — ce sont les callbacks de `ChoixRestaurationICloudVue`, et la
            // fermeture de l'onboarding, qui le posent une fois tranché.
            etatDemarrage = .choixRestauration

        case .vide:
            etatDemarrage = .onboarding
            marquerDemarrageResolu()

        case .indetermine:
            // Compte iCloud injoignable : on laisse l'utilisateur avancer,
            // mais sans marquer la question résolue. Conclure « vide » ici
            // condamnerait définitivement des données bien réelles, juste
            // parce que le réseau manquait au mauvais moment.
            etatDemarrage = .onboarding
        }
    }

    /// Mémorise que la question du premier lancement a été tranchée sur cet
    /// appareil — évite de rejouer la détection (et son attente CloudKit) à
    /// chaque lancement suivant.
    private func marquerDemarrageResolu() {
        UserDefaults.standard.set(true, forKey: Self.cleDemarrageResolu)
    }

    /// Branche les services de préférences (renommages, masquages, aliments
    /// récents, contextes) sur le hub. Ils y sont persistés — et donc
    /// synchronisés par CloudKit — depuis leur sortie de `UserDefaults`, qui
    /// les perdait à chaque désinstallation.
    private func demarrerServicesPreferences() {
        NomsPersonnalisesService.shared.demarrer(contexte: modelContext)
        AlimentsCachesService.shared.demarrer(contexte: modelContext)
        AlimentsRecentsService.shared.demarrer(contexte: modelContext)
        RepasARevoirMasquesService.shared.demarrer(contexte: modelContext)
        ReferentielContextesService.shared.demarrer(contexte: modelContext)
    }

    /// Recharge les préférences après un import CloudKit — sans ça, celles
    /// arrivées d'un autre appareil (ou d'une restauration) resteraient
    /// invisibles jusqu'au prochain lancement, puisque chaque service tient
    /// son état en mémoire pour la lecture.
    private func rechargerServicesPreferences() {
        NomsPersonnalisesService.shared.recharger()
        AlimentsCachesService.shared.recharger()
        AlimentsRecentsService.shared.recharger()
        RepasARevoirMasquesService.shared.recharger()
        ReferentielContextesService.shared.recharger()
    }

    /// Vrai si le hub contient déjà au moins une donnée, ou si un profil
    /// valide existe — dans les deux cas, l'app n'est pas dans l'état
    /// « premier lancement, aucune donnée nulle part ».
    private func detecterDonneesExistantes(_ contexte: ModelContext) -> Bool {
        let profils = (try? contexte.fetch(FetchDescriptor<ProfilUtilisateur>())) ?? []
        if profils.contains(where: { $0.estValide }) { return true }

        let comptes: [Int] = [
            (try? contexte.fetchCount(FetchDescriptor<GlucoseReading>())) ?? 0,
            (try? contexte.fetchCount(FetchDescriptor<Injection>())) ?? 0,
            (try? contexte.fetchCount(FetchDescriptor<Repas>())) ?? 0,
            (try? contexte.fetchCount(FetchDescriptor<Aliment>())) ?? 0,
            (try? contexte.fetchCount(FetchDescriptor<ActiviteSportive>())) ?? 0,
            (try? contexte.fetchCount(FetchDescriptor<EtatDeclare>())) ?? 0,
            (try? contexte.fetchCount(FetchDescriptor<Medicament>())) ?? 0,
            (try? contexte.fetchCount(FetchDescriptor<PeriodePause>())) ?? 0,
            (try? contexte.fetchCount(FetchDescriptor<Resucrage>())) ?? 0,
        ]
        return comptes.contains { $0 > 0 }
    }

}

#if DEBUG
extension AppTabVues {

    /// Container in-memory portant l'intégralité du schéma du hub (mêmes
    /// types que `DiavizApp.modelContainer`), peuplé en réutilisant les jeux
    /// d'exemple déjà maintenus par chaque service pour ses propres previews,
    /// plus l'historique dédié `RepasService.echantillonsApercuR1()` (hors
    /// fenêtre CGM, verdicts posés directement) qui fait franchir le seuil de
    /// R1 sur deux moments et illustre écart détecté / bien calibré /
    /// progression partielle. `EtatDeclare`/`Medicament`/`PeriodePause`
    /// restent vides, aucune saisie n'existe encore pour ces types. Pas de
    /// données ciblées pour B1 (tendance basale) ici — se vérifie mieux avec
    /// un jeu dédié sur le composant concerné, pas dans ce préréglage général.
    @MainActor
    static var conteneurApercuComplet: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: GlucoseReading.self, Injection.self, Repas.self, Aliment.self,
                 ActiviteSportive.self, EtatDeclare.self, Medicament.self, PeriodePause.self,
                 Resucrage.self, ProfilUtilisateur.self,
            configurations: config
        )
        let contexte = container.mainContext
        for lecture in ScoreService.echantillonsApercu() { contexte.insert(lecture) }
        for repas in RepasService.echantillonsApercu() + RepasService.echantillonsApercuR1() { contexte.insert(repas) }
        for injection in InjectionsService.echantillonsApercu() { contexte.insert(injection) }
        for activite in ActivitesSportService.echantillonsApercu() { contexte.insert(activite) }
        // Profil pré-rempli inséré directement dans le container plutôt que via
        // `ProfilService.shared.mettreAJour` : `ProfilService.demarrer(contexte:)`
        // (appelé par `AppTabVues.task`) fait un fetch-ou-création sur CE
        // container — une mutation posée avant coup sur le singleton serait
        // écrasée dès que `demarrer` tourne et ne trouve rien dans le container.
        contexte.insert(ProfilUtilisateur(
            prenom: "Camille",
            poidsKg: 78,
            insulineRapide: .fiasp,
            insulineLente: .tresiba,
            dureeActionInsulineHeures: 3.5,
            modeRatio: .parMoment,
            ratioUnique: nil,
            ratiosParMoment: RatiosParMoment(
                petitDejeuner: 8,
                dejeuner: 12,
                gouter: 15,
                diner: 10
            ),
            ratioCorrection: 35,
            horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(),
            preferencesAvancees: PreferencesAvancees()
        ))
        try? contexte.save()
        return container
    }
}

#if DEBUG
#Preview("App complète") {
    AppTabVues()
        .modelContainer(AppTabVues.conteneurApercuComplet)
}
#endif
#endif
