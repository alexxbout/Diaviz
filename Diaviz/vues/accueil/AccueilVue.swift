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
/// Push de `DetailScoreVue` au tap sur la carte score, via
/// `navigationDestination(item:)`.
struct AccueilVue: View {

    /// Binding piloté par la racine (`AppTabVues`). Local par défaut quand
    /// la vue est instanciée sans binding (previews).
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

    /// Service réel des resucrages — alimente `CarteResucrageRecent`,
    /// affichée sur l'accueil uniquement dans la fenêtre réglée au profil
    /// (`fenetreAffichageResucrageAccueilHeures`). Instance propre à cette
    /// vue, comme les autres services d'accueil ci-dessus — pas de partage
    /// via environnement.
    @State private var resucragesService = ResucragesService()

    /// Redirection vers la page Resucrage au tap sur `CarteResucrageRecent`.
    @State private var afficherResucrages = false

    /// Contexte du hub — injecté dans les services (IOB, Score) au boot.
    @Environment(\.modelContext) private var modelContext

    /// Assembleur B1 réel — instance partagée (injectée par `AppTabVues`),
    /// utilisée ici pour ajouter l'observation « nouvelle tendance basale »
    /// en tête de la pile d'insights quand le verdict vient de changer.
    @Environment(AnalyseBasaleService.self) private var analyseBasaleService

    /// Mining R1 réel — alimente l'observation « écart de ratio détecté »
    /// dans la pile d'insights (voir `insightsAffiches`).
    @Environment(AnalyseRatioService.self) private var analyseRatioService

    /// Tendance hebdomadaire de glucides — alimente `CarteGlucidesSemaine`.
    @Environment(GlucidesHebdoService.self) private var glucidesHebdoService

    /// Service hub des repas — source réelle de « Repas à revoir » et
    /// « Repas avec contexte » (courbes CGM encore en mémoire pour les repas
    /// récents).
    @Environment(RepasService.self) private var repasService

    /// Identifiants des insights supprimés par l'utilisateur (swipe gauche /
    /// appui long + confirmation). Persisté en UserDefaults : un insight au
    /// même contenu (même `id`, dérivé du contenu de l'observation, jamais
    /// aléatoire) reste masqué tant que rien n'a changé.
    @State private var idsInsightsSupprimes: Set<UUID> = InsightsAccueilPersistance.chargerSupprimes()

    /// Insight en attente de confirmation de suppression (alert). `nil` =
    /// aucune confirmation en cours.
    @State private var insightASupprimer: Insight?

    /// Pilote l'ouverture de la sheet de détail « Écart de ratio » — deux
    /// points d'entrée (carte insight R1 et `CarteAnalyseRatio`), même sheet.
    @State private var afficherDetailEcartRatio = false

    /// Pile affichée : uniquement des observations **réelles** (B1 basale +
    /// R1 écart de ratio), moins celles déjà supprimées par l'utilisateur.
    ///
    /// Les insights mockés (`InsightsAccueilServiceMock`) ne sont
    /// volontairement plus branchés ici — voir de vraies fausses données sur
    /// un écran de suivi de santé était trompeur. Le fichier reste en place
    /// (mocks réutilisables pour des previews/tests futurs), simplement plus
    /// lu par l'accueil réel.
    private var insightsAffiches: [Insight] {
        let reels = [
            analyseBasaleService.insightNouvelleTendance,
            analyseRatioService.insightEcartDetecte,
        ].compactMap { $0 }
        return reels.filter { !idsInsightsSupprimes.contains($0.id) }
    }

    /// Injections et activités du hub — servent uniquement à superposer les
    /// faits (bolus, correction, lente, sport) sur les courbes des cartes
    /// « Repas à revoir ». Chargées une fois au `task` de la page plutôt qu'à
    /// chaque recalcul de la propriété dérivée.
    @State private var injectionsRecentes: [Injection] = []
    @State private var activitesRecentes: [ActiviteSportive] = []

    /// Charge d'activité continue (7j vs normale perso 4 semaines) —
    /// recalculée depuis `activitesRecentes` (même fenêtre 45j, largement
    /// suffisante pour la normale sur 4 semaines).
    @State private var chargeContinueService = ChargeContinueService()

    /// Repas signalés « à revoir » : les groupes **récurrents** dont la
    /// dernière occurrence est sortie de cible (`CalculRepasARevoir`) et les
    /// repas **isolés** (contexte libre et/ou ajustement, verdict mauvais,
    /// `CalculRepasIsoles`), fusionnés en une seule liste triée par
    /// sévérité — une seule section les affiche désormais.
    ///
    /// Les deux calculateurs restent distincts (recherche de récurrence vs
    /// fait isolé, seuils de fiabilité différents) : seule la présentation
    /// fusionne.
    private var repasARevoir: [RepasARevoir] {
        let horaires = ProfilService.shared.profil.horairesRepas
        let occurrencesMinimales = ProfilService.shared.profil.preferencesAvancees.occurrencesMinimalesRepasARevoir
            ?? CalculRepasARevoir.occurrencesMinimalesParDefaut
        let idsMasques = RepasARevoirMasquesService.shared.idsMasques
        let seuils = ProfilService.shared.profil.seuilsGlycemiques
        let recurrents = CalculRepasARevoir.analyser(
            repas: repasService.repas,
            injections: injectionsRecentes,
            activites: activitesRecentes,
            horairesRepas: horaires,
            seuils: seuils,
            occurrencesMinimales: occurrencesMinimales,
            idsMasques: idsMasques
        )
        let isoles = CalculRepasIsoles.analyser(
            repas: repasService.repas,
            injections: injectionsRecentes,
            activites: activitesRecentes,
            horairesRepas: horaires,
            seuils: seuils,
            idsMasques: idsMasques
        )
        return (recurrents + isoles)
            .sorted(by: CalculRepasARevoir.plusSevereEnPremier)
    }

    /// Progression affichée sous le placeholder « Glucides » — jours avec
    /// repas cette semaine vers `joursMinimumParSemaine`. `nil` tant qu'aucun
    /// repas n'a été enregistré cette semaine.
    private var progressionGlucides: CartePlaceholderAccueil.Progression? {
        let jours = glucidesHebdoService.joursAvecRepasCetteSemaine
        let requis = CalculGlucidesHebdo.joursMinimumParSemaine
        guard jours > 0, jours < requis else { return nil }
        return .init(
            actuel: jours, requis: requis,
            libelle: "\(jours) jour\(jours > 1 ? "s" : "") avec repas cette semaine sur \(requis)"
        )
    }

    /// Charge les faits du hub utilisés en superposition des courbes. Fenêtre
    /// alignée sur celle des cartes (`CalculRepasARevoir.fenetreJours`) : rien
    /// à remonter au-delà, les courbes CGM n'existent plus en mémoire.
    private func chargerFaitsPourCourbes() {
        let borne = Date().addingTimeInterval(-Double(CalculRepasARevoir.fenetreJours) * 86_400)
        let descripteurInjections = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.heure >= borne },
            sortBy: [SortDescriptor(\.heure)]
        )
        let descripteurActivites = FetchDescriptor<ActiviteSportive>(
            predicate: #Predicate { $0.dateDebut >= borne },
            sortBy: [SortDescriptor(\.dateDebut)]
        )
        injectionsRecentes = (try? modelContext.fetch(descripteurInjections)) ?? []
        activitesRecentes = (try? modelContext.fetch(descripteurActivites)) ?? []
        chargeContinueService.recalculer(depuis: activitesRecentes)
    }

    /// Contexte de la carte « Insuline lente » — **réel**, construit depuis la
    /// dernière injection lente du hub + le profil (`construireContexteLente()`).
    /// `nil` tant que pas chargé → carte masquée.
    @State private var contexteLente: ContexteLente?

    /// Pilote le push de `PageTousRepasARevoir` (bouton « Tout voir » de
    /// `SectionRepasARevoir`).
    @State private var afficherTousRepasARevoir = false

    /// Pilote l'ouverture de la sheet d'enregistrement de la lente.
    @State private var sheetLenteOuverte: Bool = false

    /// Pilote le push de `PageGlucides` — porte la synthèse plutôt qu'un
    /// simple booléen (même pattern que `jourDetailScore`), pour ne jamais
    /// pousser la page avec des données obsolètes ou absentes.
    @State private var syntheseGlucidesPourPage: SyntheseGlucidesHebdo?

    /// Pilote le push de `PageChargeActivite`. Bool plutôt que
    /// `navigationDestination(item:)` : `SyntheseChargeContinue` n'a pas
    /// d'identité naturelle (pas d'`id`), contrairement à
    /// `SyntheseGlucidesHebdo` — la page relit `chargeContinueService.synthese`
    /// au moment du push.
    @State private var afficherPageCharge = false

    /// Pilote la sheet Profil ouverte depuis le placeholder « aucun ratio
    /// configuré ». `EnTetePage` porte déjà sa propre sheet pour l'avatar :
    /// les deux points d'entrée sont indépendants, aucun état partagé (le
    /// composant d'en-tête est réutilisé tel quel sur les 4 onglets).
    @State private var afficherProfil = false

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
                        // Entièrement masquée tant qu'aucune observation
                        // n'existe (pas de placeholder).
                        SectionInsights(
                            insights: insightsAffiches,
                            onDemandeSuppression: { insightASupprimer = $0 },
                            onTap: { insight in
                                // Seul l'insight R1 a une destination pour
                                // l'instant — B1 reste sans effet au tap,
                                // cohérent avec le doc « Ce qui reste à faire ».
                                if insight.id == analyseRatioService.insightEcartDetecte?.id {
                                    afficherDetailEcartRatio = true
                                }
                            }
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

                                // Carte « Dernier resucrage » — visible
                                // uniquement dans la fenêtre réglée au profil
                                // après la prise, comme la carte lente
                                // ci-dessus. Passé le délai, elle disparaît
                                // de l'accueil (elle reste toujours visible
                                // sur la page Resucrage dédiée).
                                if CarteResucrageRecent.estDansLaFenetre(
                                    dernier: resucragesService.dernierResucrage,
                                    fenetreHeures: ProfilService.shared.profil.preferencesAvancees.fenetreAffichageResucrageAccueilHeures
                                        ?? CarteResucrageRecent.fenetreAccueilParDefautHeures
                                ) {
                                    CarteResucrageRecent(
                                        dernier: resucragesService.dernierResucrage,
                                        onTap: { afficherResucrages = true }
                                    )
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)
                                        ))
                                }

                                // Tant que l'historique ne couvre pas assez de
                                // jours (voir
                                // `CalculGlucidesHebdo.joursMinimumParSemaine`),
                                // la moyenne n'est pas calculée — dégradation
                                // gracieuse plutôt qu'un chiffre tiré d'un trou
                                // de saisie — mais la place est tenue par un
                                // placeholder qui montre où en est la collecte.
                                if let synthese = glucidesHebdoService.synthese {
                                    CarteGlucidesSemaine(
                                        synthese: synthese,
                                        onTap: { syntheseGlucidesPourPage = synthese }
                                    )
                                } else {
                                    CartePlaceholderAccueil(
                                        icone: "chart.bar.xaxis",
                                        message: "La moyenne de glucides par jour, comparée à la semaine dernière, s'affichera ici.",
                                        progression: progressionGlucides
                                    )
                                }

                                if let synthese = chargeContinueService.synthese {
                                    CarteChargeActivite(
                                        synthese: synthese,
                                        onTap: { afficherPageCharge = true }
                                    )
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

                        // Section « Repas à revoir » — repas récurrents ET
                        // contextualisés sortis de cible, fusionnés en une
                        // seule section (le plus sévère en carte détaillée,
                        // les suivants en lignes compactes). Vide, elle
                        // affiche son placeholder. « Tout voir » pousse
                        // `PageTousRepasARevoir` (toutes les cartes en grand,
                        // sans version repliée).
                        SectionRepasARevoir(
                            repas: repasARevoir,
                            onToutVoir: { afficherTousRepasARevoir = true }
                        )
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

                        // Verdict du mining R1 (ratio observé) par groupe —
                        // ou, sans aucun ratio configuré, un placeholder
                        // ouvrant le profil.
                        CarteAnalyseRatio(
                            onTap: { afficherDetailEcartRatio = true },
                            onOuvrirProfil: { afficherProfil = true }
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
                    // Marge horizontale système (`.padding(.horizontal)`,
                    // sans valeur) et non 16 codé en dur — même convention
                    // que `JournalVue` et `EnTetePage`.
                    .padding(.horizontal)
                    .padding(.vertical, 16)
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
            .navigationDestination(isPresented: $afficherTousRepasARevoir) {
                PageTousRepasARevoir(repas: repasARevoir)
            }
            .navigationDestination(item: $syntheseGlucidesPourPage) { synthese in
                PageGlucides(synthese: synthese)
            }
            .navigationDestination(isPresented: $afficherPageCharge) {
                // Fallback vide inatteignable en pratique : la carte qui
                // déclenche ce push n'existe que si `synthese` est déjà
                // non-nil. `.mockBaisse` (préview) n'est pas dispo en
                // Release, d'où cette synthèse neutre plutôt qu'un `!`.
                PageChargeActivite(
                    synthese: chargeContinueService.synthese ?? SyntheseChargeContinue(
                        serieJournaliere: [], chargeSemaine: 0, normaleHebdo: 0,
                        ecartRelatif: nil, tendance: .stable
                    )
                )
            }
            .navigationDestination(isPresented: $afficherResucrages) {
                ListeResucrages()
            }
            .sheet(isPresented: $afficherProfil) {
                // Même présentation que la sheet de l'avatar
                // (`EnTetePage`) — l'utilisateur doit retrouver le même
                // écran quel que soit le point d'entrée.
                NavigationStack {
                    ProfilVue()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
            .sheet(isPresented: $afficherDetailEcartRatio) {
                // Tout groupe ayant au moins un repas exploitable — c'est le
                // seuil par tranche (`effectifMinimalBucket`) qui décide seul
                // de ce qui est comparable, la sheet montre le reste tel quel.
                SheetEcartRatio(
                    sections: analyseRatioService.analyse.sections.filter { !$0.entrees.isEmpty },
                    apercusChangementRatio: analyseRatioService.apercusChangementRatio
                )
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
                resucragesService.demarrer(contexte: modelContext)
                contexteLente = construireContexteLente()
                chargerFaitsPourCourbes()
            }
            .onAppear {
                iobService.rafraichir()
                metriquesService.recharger()
                contexteLente = construireContexteLente()
                // Un repas ou une injection ajoutés depuis un autre onglet
                // doivent apparaître sur les courbes au retour sur l'accueil.
                chargerFaitsPourCourbes()
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
        .environment(GlucidesHebdoService.apercu())
        .modelContainer(ScoreService.conteneurApercu())
}

#if DEBUG
#Preview("Profil neuf") {
    AccueilVue()
        .environment(ProfilService.mockVide())
        .environment(AnalyseBasaleService())
        .environment(RepasService.apercu())
        .environment(AnalyseRatioService())
        .environment(GlucidesHebdoService.apercu())
        .modelContainer(ScoreService.conteneurApercu())
}

/// Compte neuf, hub vide : toutes les sections tiennent leur place en
/// placeholder plutôt que de laisser une page quasi blanche.
#Preview("Aucune donnée (placeholders)") {
    AccueilVue()
        .environment(ProfilService.mockVide())
        .environment(AnalyseBasaleService())
        .environment(RepasService())
        .environment(AnalyseRatioService())
        .environment(GlucidesHebdoService.apercu(synthese: nil, joursAvecRepasCetteSemaine: 0))
        .modelContainer(ScoreService.conteneurApercu())
}

/// Quelques jours de saisie : les placeholders affichent leur progression
/// chiffrée vers les seuils déjà appliqués par les calculateurs.
#Preview("Collecte en cours (progression)") {
    AccueilVue()
        .environment(ProfilService.mockComplet())
        .environment(AnalyseBasaleService())
        .environment(RepasService())
        .environment(AnalyseRatioService())
        .environment(GlucidesHebdoService.apercu(synthese: nil, joursAvecRepasCetteSemaine: 2))
        .modelContainer(ScoreService.conteneurApercu())
}
#endif
#endif
