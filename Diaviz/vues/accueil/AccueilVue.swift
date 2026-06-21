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

    /// Repas signalés « à revoir » (sortis de cible, contenant au
    /// moins un aliment estimé, hors fenêtre de sport). Service mock
    /// le temps que la couche ML produise la vraie liste.
    @State private var repasARevoir: [RepasARevoir] = RepasAReevoirServiceMock.mock()

    /// Contexte de la carte « Insuline lente » — **réel**, construit depuis la
    /// dernière injection lente du hub + le profil (`construireContexteLente()`).
    /// `nil` tant que pas chargé → carte masquée.
    @State private var contexteLente: ContexteLente?

    /// Pilote l'ouverture de la sheet d'enregistrement de la lente.
    @State private var sheetLenteOuverte: Bool = false

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
                        SectionInsights(insights: insights)

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
                        }

                        // Section « Repas à revoir » — scroll horizontal
                        // des repas sortis de cible avec aliments
                        // estimés. Auto-masquée quand le tableau est
                        // vide. Le scroll déborde edge-to-edge en
                        // annulant le padding 16pt du VStack parent.
                        SectionRepasARevoir(repas: repasARevoir)

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
                    // Anime l'insertion/suppression de la carte lente
                    // (et toute future entrée/sortie de section) en
                    // fonction de l'état calculé. La valeur observée
                    // est l'`etatLente` directement : tout passage
                    // entre `nil`, `.doux`, `.urgent`, `.alerte`
                    // déclenche la même spring. Désactivée si l'
                    // utilisateur a activé « Réduire les animations ».
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
                        value: etatLente
                    )
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
            .sheet(isPresented: $sheetLenteOuverte) {
                // Sheet existante d'enregistrement de la lente. Les
                // valeurs par défaut (`dose = 18`, `heure = now`)
                // suffisent au pré-remplissage du mock ; le binding
                // bascule `priseAujourdhui` à `true` côté
                // `onValider` → la carte disparaît avec animation.
                SheetInsulineLente(
                    derniereZoneLente: nil,
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
            }
        }
    }

    /// État courant du rappel lente — `nil` quand la carte doit être
    /// masquée (trop tôt, ou lente déjà prise aujourd'hui).
    private var etatLente: EtatRappelLente? {
        contexteLente.flatMap { EtatRappelLente.calculer(contexte: $0) }
    }

    /// Construit le contexte du rappel de lente depuis le hub (dernière injection
    /// lente) et le profil. Heure habituelle = 22h en V1 (à terme depuis le profil).
    ///
    /// **Ancrage intelligent** (corrige les bugs de frontière minuit) : on vise
    /// la **dernière** occurrence de 22h tant que sa prise n'est pas faite (un
    /// oubli reste donc en alerte, même après minuit) ; dès qu'elle est faite, on
    /// vise la **prochaine** (rappel doux anticipé le soir suivant). Le masquage
    /// découle entièrement de cet ancrage via `EtatRappelLente.calculer`
    /// (`priseAujourdhui` n'est plus utilisé pour masquer).
    private func construireContexteLente() -> ContexteLente {
        let cal = Calendar.current
        let now = Date()

        // Dernière / prochaine occurrence de l'heure habituelle (22h).
        let heure22Aujourdhui = HeureDuJour(heure: 22, minute: 0).date(pour: now)
        let derniere22h = now >= heure22Aujourdhui
            ? heure22Aujourdhui
            : (cal.date(byAdding: .day, value: -1, to: heure22Aujourdhui) ?? heure22Aujourdhui)
        let prochaine22h = cal.date(byAdding: .day, value: 1, to: derniere22h) ?? derniere22h

        // Dernière injection lente du hub.
        let descripteur = FetchDescriptor<Injection>(
            sortBy: [SortDescriptor(\.heure, order: .reverse)]
        )
        let derniereLente = (try? modelContext.fetch(descripteur))?.first { $0.type == .lente }

        // La prise de la fenêtre courante (à partir de derniere22h − 1h) est-elle
        // faite ? Si oui, on cible la prochaine ; sinon on reste sur la courante.
        let debutFenetre = cal.date(byAdding: .hour, value: -1, to: derniere22h) ?? derniere22h
        let priseCouranteFaite = (derniereLente?.heure).map { $0 >= debutFenetre } ?? false
        let heureCible = priseCouranteFaite ? prochaine22h : derniere22h

        let profil = ProfilService.shared.profil
        return ContexteLente(
            heureHabituelle: heureCible,
            nomInsuline: derniereLente?.nomMedicament ?? profil.insulineLente.rawValue,
            doseHabituelle: derniereLente?.dose ?? 0,
            dernierePrise: derniereLente?.heure ?? .distantPast,
            dernierSite: derniereLente?.libelleSite ?? "—",
            priseAujourdhui: false
        )
    }

    /// Date du jour calendaire courant (00h locale) — sert d'ancre
    /// pour la navigation vers `DetailScoreVue` et de pivot pour
    /// l'historique 7 jours.
    /// Jour de référence du score = **jour métabolique en cours** (06h→06h), pas
    /// le jour calendaire. Avant 06h c'est encore la veille → la carte et le
    /// détail n'affichent pas le jour suivant à tort (même correctif que la
    /// page détail / les barres semaine).
    private var aujourdhui: Date {
        scoreService.jourCourant
    }

    /// Contenu de la carte score, recalculé à chaque render via les
    /// computed properties du service — `scoreDuJour` et
    /// `heuresDataDuJour` sont en temps réel.
    private var contenuScore: ContenuCarteScore {
        let historique = scoreService.historiqueSept(jusquA: aujourdhui)
            .map { $0.score }
        return ContenuCarteScore(
            score: scoreService.scoreDuJour,
            date: aujourdhui,
            historique: historique,
            heuresJourEcoulees: scoreService.heuresDataDuJour
        )
    }
}

#if DEBUG
#Preview("Avec profil complet") {
    AccueilVue()
        .environment(ProfilService.mockComplet())
        .modelContainer(ScoreService.conteneurApercu())
}

#Preview("Profil neuf") {
    AccueilVue()
        .environment(ProfilService.mockVide())
        .modelContainer(ScoreService.conteneurApercu())
}
#endif
