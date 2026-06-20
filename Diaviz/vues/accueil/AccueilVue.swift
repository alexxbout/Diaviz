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

    /// Service mocké pour la grille de métriques. Les vues filles n'en
    /// ont pas besoin — on consomme `metriques` directement ici.
    /// Sera remplacé par une lecture `@Environment` quand la couche
    /// d'analyses sera branchée.
    @State private var metriquesService = AccueilMetriquesServiceMock.shared

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

    /// Contexte de la carte « Insuline lente » — mocké en état urgent
    /// pour démontrer le rappel sur l'accueil. Sera dérivé du
    /// `ProfilService` et du service d'injections quand la couche
    /// médication sera branchée sur l'accueil.
    @State private var contexteLente: ContexteLente = .mockUrgent

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
                    // Spacing 28pt entre les sections (score, observations,
                    // aperçu) pour clarifier la hiérarchie : chaque bloc
                    // respire et se lit comme une unité distincte.
                    VStack(spacing: 28) {
                        // Carte score du jour — recalculée en temps
                        // réel (06h-06h), avec la dernière barre de
                        // l'historique rendue en mode "en cours".
                        CarteScoreQuotidien(
                            contenu: contenuScore,
                            style: .gradient,
                            onTap: { jourDetailScore = aujourdhui }
                        )

                        // Carte contextuelle « Insuline lente » —
                        // visible uniquement si l'utilisateur entre
                        // dans la fenêtre de rappel (≥ heure habituelle
                        // − 1h) sans avoir encore pris sa lente. Le
                        // calcul de visibilité vit dans
                        // `EtatRappelLente.calculer(...)`. La carte
                        // entre et sort en spring avec une transition
                        // depuis le haut, désactivée quand l'utilisateur
                        // a activé « Réduire les animations ».
                        if let etatLente {
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

                        // Section observations ML — TabView paginé
                        // sous la carte score. Auto-masquée quand le
                        // tableau d'insights est vide pour ne pas
                        // laisser une coquille vide entre le score
                        // et la grille des métriques.
                        SectionInsights(insights: insights)

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
                    onValider: { _ in
                        contexteLente = ContexteLente(
                            heureHabituelle: contexteLente.heureHabituelle,
                            nomInsuline: contexteLente.nomInsuline,
                            doseHabituelle: contexteLente.doseHabituelle,
                            dernierePrise: Date(),
                            dernierSite: contexteLente.dernierSite,
                            priseAujourdhui: true
                        )
                    }
                )
            }
            .task { iobService.demarrer(contexte: modelContext) }
            .onAppear { iobService.rafraichir() }
        }
    }

    /// État courant du rappel lente — `nil` quand la carte doit être
    /// masquée (trop tôt, ou lente déjà prise aujourd'hui).
    private var etatLente: EtatRappelLente? {
        EtatRappelLente.calculer(contexte: contexteLente)
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
