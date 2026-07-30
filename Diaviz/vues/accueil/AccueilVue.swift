//
//  AccueilVue.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI
import SwiftData

/// Page d'accueil — carte score du jour (en temps réel, convention
/// 06h-06h) et grille d'aperçu instantané sur l'état courant.
///
/// Header App Store style (titre + avatar sur la même ligne) géré par
/// le composant partagé `EnTetePage`, présent à l'identique sur
/// les quatre onglets racines.
///
/// Push de `DetailScoreVue` depuis deux entrées :
///   - Tap sur la carte → push direct via `navigationDestination(item:)`
///   - Bouton « Voir les détails » de `SheetScoreMatin` → la racine
///     (`AppTabVues`) écrit dans `$jourDetailScore` après dismiss de
///     la sheet, ce qui déclenche le même push.
struct AccueilVue: View {

    /// Binding piloté par la racine (`AppTabVues`) pour pouvoir pousser
    /// le détail depuis la sheet du matin. Local par défaut quand la
    /// vue est instanciée sans binding (previews).
    @Binding var jourDetailScore: Date?

    /// Service **réel** des métriques d'accueil (hypos du jour, dernière
    /// injection, dernier repas) calculées depuis le hub. La carte IOB est
    /// alimentée à part par `iobService`.
    @State private var metriquesService = MetriquesAccueilService()

    /// Service IOB **réel** — calcule l'insuline active depuis le hub (injections
    /// rapides + DIA du profil). Alimente la carte « Insuline active » ; les 3
    /// autres cartes restent sur le mock pour l'instant.
    @State private var iobService = IOBService()

    /// Service réel du score du jour et de son historique. Lit le hub
    /// `GlucoseReading` (injecté via `modelContext` au boot) et calcule le GRI
    /// à la volée. Expose `scoreDuJour` / `heuresDataDuJour` (live) +
    /// `historiqueSept`. API identique à l'ancien mock.
    @State private var scoreService = ScoreService()

    /// Contexte du hub — injecté dans les services (IOB, Score) au boot.
    @Environment(\.modelContext) private var modelContext

    /// Observations ML affichées sous la carte score — section masquée
    /// si le tableau est vide. Service mock pour l'instant ; sera
    /// remplacé par une vraie source quand la couche ML sera branchée.
    @State private var insights: [Insight] = InsightsAccueilServiceMock.mockComplet()

    /// Assembleur B1 réel — instance partagée (injectée par `AppTabVues`),
    /// utilisée ici pour ajouter l'observation « nouvelle tendance basale »
    /// en tête de la pile d'insights quand le verdict vient de changer.
    @Environment(AnalyseBasaleService.self) private var analyseBasaleService

    /// Service hub des repas — source réelle de « Repas à revoir » et
    /// « Repas avec contexte » (courbes CGM encore en mémoire pour les repas
    /// récents).
    @Environment(RepasService.self) private var repasService

    /// Identifiants des insights supprimés par l'utilisateur (swipe gauche /
    /// appui long + confirmation). Persisté en UserDefaults : un insight au
    /// même contenu (même `id`, dérivé de son contenu pour l'observation
    /// réelle) reste masqué tant que rien n'a changé. Les insights mockés,
    /// eux, ont un UUID aléatoire régénéré à chaque lancement — leur
    /// suppression ne survit donc pas à un redémarrage de l'app.
    @State private var idsInsightsSupprimes: Set<UUID> = InsightsAccueilPersistance.chargerSupprimes()

    /// Insight en attente de confirmation de suppression (alert). `nil` =
    /// aucune confirmation en cours.
    @State private var insightASupprimer: Insight?

    /// Pile affichée : l'observation B1 réelle (si nouvelle) en tête, suivie
    /// des mocks, moins les insights déjà supprimés par l'utilisateur.
    private var insightsAffiches: [Insight] {
        let reels = [analyseBasaleService.insightNouvelleTendance].compactMap { $0 }
        return (reels + insights).filter { !idsInsightsSupprimes.contains($0.id) }
    }

    /// Repas signalés « à revoir » — groupes de repas similaires récurrents
    /// dont la dernière occurrence est sortie de cible (`CalculRepasARevoir`).
    /// Masquée tant que l'historique global n'atteint pas le seuil R1 (30
    /// repas analysés, gate appliquée dans le calculateur).
    private var repasARevoir: [RepasARevoir] {
        CalculRepasARevoir.analyser(
            repas: repasService.repas,
            horairesRepas: ProfilService.shared.profil.horairesRepas
        )
    }

    /// Repas isolés avec contexte libre et verdict mauvais — aucun seuil de
    /// données (ce n'est pas une inférence statistique, juste un fait affiché).
    private var repasAvecContexte: [RepasARevoir] {
        CalculRepasContexte.analyser(
            repas: repasService.repas,
            horairesRepas: ProfilService.shared.profil.horairesRepas
        )
    }

    /// Contexte de la carte « Insuline lente » — **réel**, construit depuis la
    /// dernière injection lente du hub + le profil (`construireContexteLente()`).
    /// `nil` tant que pas chargé → carte masquée.
    @State private var contexteLente: ContexteLente?

    /// Pilote l'ouverture de la sheet d'enregistrement de la lente.
    @State private var sheetLenteOuverte: Bool = false

    /// `false` jusqu'au premier remplissage des données. Tant qu'il est faux,
    /// l'`.animation` de la carte lente est neutralisée : le passage initial
    /// `nil`→valeur d'`etatLente` (données async au boot) n'anime rien — évite le
    /// « morphing » des cartes au lancement.
    @State private var animationsLente: Bool = false

    /// Respecte « Réduire les animations » système — l'`.animation`
    /// d'apparition/disparition de la carte lente la désactive alors.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(jourDetailScore: Binding<Date?> = .constant(nil)) {
        self._jourDetailScore = jourDetailScore
    }

    /// Accès convenance au snapshot courant.
    private var metriques: MetriquesAccueil {
        metriquesService.metriques
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Accueil")

                ScrollView {
                    // Spacing 28pt entre les sections (tendances,
                    // « Aujourd'hui », repas, aperçu) pour clarifier la
                    // hiérarchie : chaque bloc respire et se lit comme
                    // une unité distincte.
                    VStack(spacing: 28) {
                        // Section « Nouvelles tendances » — pile des
                        // observations ML, désormais en tête de page.
                        // Auto-masquée quand le tableau d'insights est
                        // vide pour ne pas laisser une coquille en haut.
                        SectionInsights(
                            insights: insightsAffiches,
                            onDemandeSuppression: { insightASupprimer = $0 }
                        )

                        // Section « Aujourd'hui » — carte score du jour
                        // (recalculée en temps réel 06h-06h) et, si la
                        // fenêtre de rappel est ouverte, la carte
                        // contextuelle « Insuline lente ». Les deux
                        // cartes sont groupées sous un même en-tête, comme
                        // « Aperçu du jour » plus bas (spacing 8 titre →
                        // contenu pour que le titre "appartienne" au bloc).
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Aujourd'hui")
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                                .padding(.leading, 4)
                                .accessibilityAddTraits(.isHeader)

                            VStack(spacing: 12) {
                                CarteScoreQuotidien(
                                    contenu: contenuScore,
                                    style: .gradient,
                                    onTap: { jourDetailScore = aujourdhui }
                                )

                                // Carte « Insuline lente » — visible
                                // uniquement dans la fenêtre de rappel
                                // (≥ heure habituelle − 1h) sans prise
                                // enregistrée ; visibilité calculée dans
                                // `EtatRappelLente.calculer(...)`. Entre et
                                // sort en spring avec une transition depuis
                                // le haut, désactivée si « Réduire les
                                // animations ».
                                if let etatLente, let contexteLente {
                                    CarteLenteRappel(
                                        etat: etatLente,
                                        contexte: contexteLente,
                                        onTapAjouter: { sheetLenteOuverte = true }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)
                                    ))
                                }
                            }
                            // Anime UNIQUEMENT l'insertion/sortie de la carte
                            // lente. Portée restreinte à ce VStack (et non au
                            // grand VStack du ScrollView) : sinon le passage
                            // nil→valeur d'`etatLente` au boot — quand les données
                            // async arrivent — animait le re-layout de TOUTES les
                            // cartes (« morphing » 50%→100%). `animationsLente`
                            // reste false au tout premier rendu pour ne pas animer
                            // non plus l'apparition initiale de la carte au boot.
                            .animation(
                                animationsLente && !reduceMotion
                                    ? .spring(response: 0.4, dampingFraction: 0.8) : nil,
                                value: etatLente
                            )
                        }

                        // Section « Repas à revoir » — scroll horizontal
                        // des repas sortis de cible avec aliments
                        // estimés. Auto-masquée quand le tableau est
                        // vide. Le scroll déborde edge-to-edge en
                        // annulant le padding 16pt du VStack parent.
                        SectionRepasARevoir(repas: repasARevoir)
                            // Anime uniquement l'apparition/disparition de
                            // cette section — pas tout le VStack — pour que
                            // le peuplement post-fetch (RepasService charge
                            // en arrière-plan, ne bloque jamais l'affichage
                            // initial de la page) se voie comme un fondu
                            // doux plutôt qu'un saut de layout brutal.
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.3),
                                value: repasARevoir.count
                            )

                        SectionRepasContexte(repas: repasAvecContexte)
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.3),
                                value: repasAvecContexte.count
                            )

                        // Grille de 4 cartes métriques — aperçu
                        // instantané de l'état courant. Le service
                        // mock est instancié localement le temps que
                        // la couche d'analyses soit branchée. Le
                        // titre de section est groupé avec la grille
                        // (spacing 8) pour qu'il "appartienne" à elle
                        // visuellement plutôt qu'au bloc d'au-dessus.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Aperçu du jour")
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                                .padding(.leading, 4)
                                .accessibilityAddTraits(.isHeader)

                            GrilleMetriquesAccueil(
                                metriques: metriques,
                                iobValeur: iobService.iobCourant,
                                iobPoints: iobService.courbe
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .task {
                // Injecte le contexte du hub au boot et charge les 30
                // derniers jours de glycémies pour le calcul du score.
                scoreService.demarrer(contexte: modelContext)
            }
            .navigationDestination(item: $jourDetailScore) { jour in
                DetailScoreVue(jourInitial: jour)
            }
            .alert(
                "Supprimer cette tendance ?",
                isPresented: Binding(
                    get: { insightASupprimer != nil },
                    set: { if !$0 { insightASupprimer = nil } }
                )
            ) {
                Button("Supprimer", role: .destructive) { confirmerSuppressionInsight() }
                Button("Annuler", role: .cancel) { insightASupprimer = nil }
            } message: {
                Text("« \(insightASupprimer?.titre ?? "") » disparaîtra de l'accueil.")
            }
            .sheet(isPresented: $sheetLenteOuverte) {
                // Sheet d'enregistrement de la lente, préremplie : dose =
                // dernière dose enregistrée (`doseHabituelle` du contexte,
                // si > 0), type = insuline lente du profil. `heure = now`.
                // Le binding bascule `priseAujourdhui` côté `onValider` → la
                // carte disparaît avec animation.
                SheetInsulineLente(
                    derniereZoneLente: nil,
                    doseParDefaut: contexteLente.flatMap { $0.doseHabituelle > 0 ? $0.doseHabituelle : nil },
                    nomMedicamentParDefaut: ProfilService.shared.profil.insulineLente.rawValue,
                    onValider: { injection in
                        // Enregistre la lente dans le hub (saisie manuelle), puis
                        // rafraîchit le rappel, les métriques et l'IOB.
                        modelContext.insert(injection)
                        try? modelContext.save()
                        contexteLente = construireContexteLente()
                        metriquesService.recharger()
                        iobService.rafraichir()
                    }
                )
            }
            .task {
                iobService.demarrer(contexte: modelContext)
                metriquesService.demarrer(contexte: modelContext)
                contexteLente = construireContexteLente()
            }
            .onAppear {
                iobService.rafraichir()
                metriquesService.recharger()
                contexteLente = construireContexteLente()
                // Active l'animation de la carte lente au tick SUIVANT : le
                // changement nil→valeur d'`etatLente` de ce cycle (boot) reste
                // donc non animé ; seuls les changements ultérieurs (prise de
                // lente, fenêtre de rappel qui s'ouvre) le sont.
                if !animationsLente {
                    Task { @MainActor in animationsLente = true }
                }
            }
        }
    }

    /// État courant du rappel lente — `nil` quand la carte doit être
    /// masquée (trop tôt, ou lente déjà prise aujourd'hui).
    private var etatLente: EtatRappelLente? {
        contexteLente.flatMap { EtatRappelLente.calculer(contexte: $0) }
    }

    /// Construit le contexte du rappel de lente depuis le hub (dernière injection
    /// lente) et le profil.
    ///
    /// **Ancrage adaptatif** : l'heure habituelle n'est plus une heure de mur
    /// fixe (22h chaque jour) mais `dernière prise + intervalle minimum du
    /// profil` — si la dernière dose a été prise à 23h10, la prochaine est
    /// attendue à 23h10 + intervalle le lendemain, pas à une heure figée. Ça
    /// suit naturellement les horaires réels de l'utilisateur au lieu de
    /// désynchroniser le rappel dès qu'une dose est prise en avance ou en
    /// retard. Tant qu'aucune lente n'a jamais été enregistrée, on retombe
    /// sur 22h comme amorce — pas de dose dont dériver l'ancrage.
    private func construireContexteLente() -> ContexteLente {
        // Dernière injection lente du hub.
        let descripteur = FetchDescriptor<Injection>(
            sortBy: [SortDescriptor(\.heure, order: .reverse)]
        )
        let derniereLente = (try? modelContext.fetch(descripteur))?.first { $0.type == .lente }

        let profil = ProfilService.shared.profil
        let heureCible = derniereLente
            .map { $0.heure.addingTimeInterval(profil.intervalleMinimumLenteEffectif * 3600) }
            ?? HeureDuJour(heure: 22, minute: 0).date()

        return ContexteLente(
            heureHabituelle: heureCible,
            nomInsuline: derniereLente?.nomMedicament ?? profil.insulineLente.rawValue,
            doseHabituelle: derniereLente?.dose ?? 0,
            dernierePrise: derniereLente?.heure ?? .distantPast,
            dernierSite: derniereLente?.libelleSite ?? "—",
            priseAujourdhui: false
        )
    }

    /// Confirme la suppression de `insightASupprimer` — l'ajoute à l'ensemble
    /// persisté et referme l'alert.
    private func confirmerSuppressionInsight() {
        guard let insight = insightASupprimer else { return }
        idsInsightsSupprimes.insert(insight.id)
        InsightsAccueilPersistance.sauvegarder(idsInsightsSupprimes)
        insightASupprimer = nil
    }

    /// Jour mis en avant par la carte score = `jourAffiche` du service : le jour
    /// métabolique en cours s'il est significatif (≥ 6h de données), sinon le
    /// dernier jour complet (bascule sur la veille le matin). Sert aussi d'ancre
    /// pour le tap → détail.
    private var aujourdhui: Date {
        scoreService.jourAffiche
    }

    /// Contenu de la carte score. `estEnCours` distingue le jour en cours
    /// (partiel, « Xh de données ») du jour complet affiché en bascule.
    private var contenuScore: ContenuCarteScore {
        let historique = scoreService.historiqueSept(jusquA: aujourdhui)
            .map { $0.score }
        return ContenuCarteScore(
            score: scoreService.scoreAffiche,
            date: aujourdhui,
            historique: historique,
            heuresJourEcoulees: scoreService.heuresDataDuJour,
            estEnCours: scoreService.jourCourantSignificatif
        )
    }
}

#if DEBUG
#Preview("Avec profil complet") {
    AccueilVue()
        .environment(ProfilService.mockComplet())
        .environment(AnalyseBasaleService())
        .environment(RepasService.apercu())
        .environment(AnalyseRatioService())
        .modelContainer(ScoreService.conteneurApercu())
}

#Preview("Profil neuf") {
    AccueilVue()
        .environment(ProfilService.mockVide())
        .environment(AnalyseBasaleService())
        .environment(RepasService.apercu())
        .environment(AnalyseRatioService())
        .modelContainer(ScoreService.conteneurApercu())
}
#endif
