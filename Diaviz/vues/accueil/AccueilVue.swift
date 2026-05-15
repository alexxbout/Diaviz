//
//  AccueilVue.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

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

    /// Service mocké pour le score du jour et son historique. Expose
    /// `scoreDuJour` et `heuresDataDuJour` recalculés à chaque accès
    /// (live), plus `historiqueSept` qui inclut la barre du jour.
    @State private var scoreService = ScoreJournalierServiceMock.shared

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
                    VStack(spacing: 16) {
                        // Carte score du jour — recalculée en temps
                        // réel (06h-06h), avec la dernière barre de
                        // l'historique rendue en mode "en cours".
                        CarteScoreQuotidien(
                            contenu: contenuScore,
                            style: .gradient,
                            onTap: { jourDetailScore = aujourdhui }
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

                            GrilleMetriquesAccueil(metriques: metriques)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(item: $jourDetailScore) { jour in
                DetailScoreVue(jourInitial: jour)
            }
        }
    }

    /// Date du jour calendaire courant (00h locale) — sert d'ancre
    /// pour la navigation vers `DetailScoreVue` et de pivot pour
    /// l'historique 7 jours.
    private var aujourdhui: Date {
        Calendar.current.startOfDay(for: Date())
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

#Preview("Avec profil complet") {
    AccueilVue()
        .environment(ProfilService.mockComplet())
}

#Preview("Profil neuf") {
    AccueilVue()
        .environment(ProfilService.mockVide())
}
