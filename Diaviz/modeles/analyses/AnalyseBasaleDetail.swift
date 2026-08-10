//
//  AnalyseBasaleDetail.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation

// MARK: - Verdict global de l'analyse basale

/// Conclusion synthétique de la sous-analyse basale (B1), telle qu'exposée
/// par la carte sommaire « Analyse du coucher » et utilisée pour router
/// vers le bon snapshot de détail (`charger(verdict:)`).
///
/// Les deux états « hors cible » (`.tropHaute`, `.tropBasse`) partagent
/// volontairement le même libellé « À revoir » côté carte pour ne pas
/// suggérer une direction de correction — l'utilisateur ouvre le détail
/// pour savoir quoi ajuster.
nonisolated enum VerdictBasale: Sendable, Equatable {

    /// Profil glycémique nocturne stable, basale calibrée.
    case adaptee

    /// Tendance haute sur la fenêtre analysée → ajustement à examiner.
    case tropHaute

    /// Tendance basse sur la fenêtre analysée → ajustement à examiner.
    case tropBasse

    /// Pas assez de nuits exploitables (capteur HS, données récentes).
    case donneesInsuffisantes
}

// MARK: - Snapshot complet de l'analyse

/// Snapshot prêt-à-afficher pour `DetailAnalyseBasaleVue` — agrège
/// verdict, métriques, courbes et texte LLM pour la fenêtre 14 nuits
/// courante. La forme est volontairement plate : toutes les valeurs
/// sont déjà calculées par le service (pas de logique dans la vue).
nonisolated struct AnalyseBasaleDetail: Identifiable, Sendable {
    let id = UUID()

    let verdict: VerdictBasale

    // MARK: Contexte « dose »
    let doseActuelle: Double
    /// Date du dernier changement de dose, ou `nil` si aucun changement
    /// récent (> 30 jours). Pilote le libellé contextuel de la carte
    /// verdict (« Depuis le changement de dose ») et le grisage des
    /// colonnes pré-changement dans la timeline.
    let changementDoseRecent: Date?

    // MARK: Métriques agrégées
    let penteMoyenne: Double          // mg/dL/h, signé
    let nuitsAnalysees: Int           // = nuits valides
    let nuitsExclues: Int

    // MARK: Décomposition pour la barre + métriques (sur les valides)
    let nuitsStables: Int
    let nuitsTendanceBasse: Int
    let nuitsTendanceHaute: Int
    let hyposNocturnes: Int
    let resucragesAvecRechute: Int
    let glycemieMoyenneReveil: Int

    // MARK: Courbes pour le chart (uniquement les nuits valides)
    let courbes: [CourbeNuit]
    let tendanceMoyenne: [PointCourbeNuit]

    // MARK: Données enrichies du graphique d'analyse (V2)
    /// Nuits prêtes à alimenter `GraphiqueAnalyseBasale`. Inclut les
    /// nuits exploitables (valides + partielles) sur la fenêtre 14 jours
    /// — on exclut les nuits sans données CGM puisqu'il n'y a rien à
    /// tracer. Le rendu par tab ("Toutes" / "Par nuit") est piloté
    /// localement par le composant.
    let nightChartData: [NightChartData]

    // MARK: Timeline 14 jours (du plus ancien au plus récent)
    let timeline: [NuitTimeline]

    // MARK: Texte LLM
    let resumeIA: String?

    // MARK: Historique de dose réel (injecté par le calculateur)
    /// Historique de dose calculé depuis les vraies injections lente du hub.
    /// `nil` pour les mocks de preview → `doseHistory` retombe sur sa
    /// génération simulée. Le service réel le renseigne via `CalculAnalyseBasale`.
    var doseHistoriqueReel: [DoseChange]? = nil

    /// `true` quand la fenêtre penchait « à revoir » mais que les nuits récentes
    /// sont revenues à stable (ex. reprise de sport). Pilote l'état « en
    /// amélioration » de la carte verdict.
    var enAmelioration: Bool = false

    /// Dérive moyenne (Δ mg/dL par nuit) des nuits récentes — l'unité de
    /// décision affichée à l'utilisateur (comparable au seuil ±30), là où
    /// `penteMoyenne` reste horaire. Renseignée par `CalculAnalyseBasale` ;
    /// approximée par les mocks.
    var deriveMoyenne: Double = 0
}

// MARK: - Modèles dérivés V3 (constat, distribution, historique de dose)

/// Tendance dégagée par l'analyse de la pente moyenne zone 3 — pilote
/// l'icône et la couleur du constat dans `CarteVerdictBasale`.
enum BasalTrend: Sendable {
    case descending
    case ascending
    case stable
}

/// État global du constat — permet à la carte de basculer entre 3
/// rendus visuels distincts (verdict / nouvelle dose en observation /
/// en attente de données).
enum BasalVerdictState: Sendable {
    case sufficient
    case recentChange
    case noData
}

/// Snapshot du constat affiché par `CarteVerdictBasale`. Pré-calculé
/// par `AnalyseBasaleDetail.basalVerdict` — la vue est purement
/// présentationnelle.
struct BasalVerdict: Sendable {
    let state: BasalVerdictState
    let slope: Double?           // pente moyenne zone 3, nil hors `.sufficient`
    /// Dérive moyenne (Δ mg/dL par nuit) des nuits récentes — l'unité montrée
    /// à l'utilisateur (comparable au seuil ±30). `nil` hors `.sufficient`.
    var derive: Double? = nil
    let trend: BasalTrend?
    let validNights: Int
    let excludedNights: Int
    let totalNights: Int
    let currentDose: Double
    let doseChangedDate: Date?
    let nightsNeeded: Int        // = max(0, 3 - validNights)
    /// La situation était « à revoir » mais s'améliore sur les nuits récentes.
    var enAmelioration: Bool = false
    /// Nb d'hypos nocturnes sur la fenêtre — mis en avant si > 0.
    var hypoCount: Int = 0
}

/// Répartition de la qualité des zones analysées (zones 2 + 3 — seules
/// concernées par le calcul de pente basale). Alimente `RepartitionNuitsVue`.
struct BasalDistribution: Sendable {
    let stableZones: Int
    let descendingZones: Int
    let ascendingZones: Int
    let excludedZones: Int
    let hypoCount: Int
    let resucrageCount: Int
    let avgWakeUpGlucose: Double
}

/// Une entrée de l'historique de dose. `endDate == nil` ⇔ dose
/// courante.
nonisolated struct DoseChange: Identifiable, Sendable {
    let id = UUID()
    let dose: Double
    let startDate: Date
    let endDate: Date?
    var isCurrent: Bool { endDate == nil }
}

// MARK: - Helpers dérivés (sur AnalyseBasaleDetail)

extension AnalyseBasaleDetail {

    /// Construit le constat à partir des métriques agrégées :
    ///   - 0 nuit valide → `.noData`
    ///   - 1-2 nuits valides → `.recentChange` (généralement après un
    ///     reset de dose ; on affiche la progression vers les 3 nuits
    ///     minimum)
    ///   - ≥ 3 nuits valides → `.sufficient`, verdict possible.
    var basalVerdict: BasalVerdict {
        let valides = nuitsAnalysees
        let nightsNeeded = max(0, 3 - valides)
        let state: BasalVerdictState = {
            if valides == 0 { return .noData }
            if valides < 3 { return .recentChange }
            return .sufficient
        }()

        // Tendance dérivée du **verdict** (récence-aware), pas de la pente brute
        // moyennée sur toute la fenêtre — sinon une vieille nuit garderait
        // l'alerte alors que le récent est stable.
        let trend: BasalTrend? = {
            guard state == .sufficient else { return nil }
            switch verdict {
            case .tropHaute:              return .descending
            case .tropBasse:              return .ascending
            case .adaptee:                return .stable
            case .donneesInsuffisantes:   return nil
            }
        }()

        return BasalVerdict(
            state: state,
            slope: state == .sufficient ? penteMoyenne : nil,
            derive: state == .sufficient ? deriveMoyenne : nil,
            trend: trend,
            validNights: valides,
            excludedNights: nuitsExclues,
            totalNights: kFenetreNuits,
            currentDose: doseActuelle,
            doseChangedDate: changementDoseRecent,
            nightsNeeded: nightsNeeded,
            enAmelioration: state == .sufficient ? enAmelioration : false,
            hypoCount: hyposNocturnes
        )
    }

    /// Catégorise les zones 2/3 de toutes les nuits du dataset selon
    /// leur pente et leur statut « analysée ». Les zones 1 (pré-endo)
    /// et 4 (dawn) sont exclues — elles ne participent jamais au
    /// calcul de pente basale.
    ///
    /// Variante non-filtrée : utilise toutes les nuits du dataset
    /// (équivaut à `basalDistribution(daysBack: kFenetreNuits)` pour
    /// le dataset standard).
    var basalDistribution: BasalDistribution {
        basalDistribution(daysBack: kFenetreNuits)
    }

    /// Variante filtrée par fenêtre temporelle — utilisée par le
    /// picker 7j / 14j / 30j de `RepartitionNuitsVue`. Les `hypoCount`,
    /// `resucrageCount` et `avgWakeUpGlucose` sont aussi recalculés
    /// **sur la fenêtre filtrée** (à partir des events de chaque nuit),
    /// pour rester cohérents avec la barre.
    func basalDistribution(daysBack: Int) -> BasalDistribution {
        let cal = Calendar.current
        let cutoffJour = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysBack, to: Date.now) ?? Date.now)
        let nuitsFiltrees = nightChartData.filter { cal.startOfDay(for: $0.date) >= cutoffJour }

        var stable = 0
        var descending = 0
        var ascending = 0
        var excluded = 0
        var hypos = 0
        var resucrages = 0
        var sommeReveil = 0.0
        for night in nuitsFiltrees {
            for zd in night.zones where zd.zone == .endormissement || zd.zone == .nuitProfonde {
                if !zd.isAnalyzed {
                    excluded += 1
                } else if let s = zd.slope {
                    // Classement sur la **dérive** (pente × durée), aligné sur le verdict.
                    let heures = zd.timeRange.upperBound.timeIntervalSince(zd.timeRange.lowerBound) / 3600
                    switch CalculAnalyseBasale.categorie(deriveMgDl: s * heures) {
                    case .tendanceBasse:  descending += 1
                    case .tendanceHaute:  ascending += 1
                    case .stable:         stable += 1
                    }
                } else {
                    stable += 1
                }
            }
            // Compteurs par nuit = source unique (mêmes chiffres que le verdict).
            hypos += night.hypoCount
            resucrages += night.rechuteCount
            sommeReveil += night.wakeUpGlucose
        }
        let moyReveil = nuitsFiltrees.isEmpty ? 0 : sommeReveil / Double(nuitsFiltrees.count)
        return BasalDistribution(
            stableZones: stable,
            descendingZones: descending,
            ascendingZones: ascending,
            excludedZones: excluded,
            hypoCount: hypos,
            resucrageCount: resucrages,
            avgWakeUpGlucose: moyReveil
        )
    }

    /// Historique de dose mocké — 4 changements sur ~75 jours, dose
    /// courante en haut. Sera remplacé par la couche médication quand
    /// elle sera branchée.
    ///
    /// Si l'analyse est en état `.noData`, on renvoie une seule
    /// entrée (la dose courante posée il y a longtemps) — c'est ce qui
    /// pilote le récap « Aucun changement depuis X jours » de
    /// `DoseHistoryCard`.
    var doseHistory: [DoseChange] {
        // Donnée réelle injectée par le calculateur si présente ; sinon la
        // génération simulée ci-dessous (previews).
        if let reel = doseHistoriqueReel { return reel }

        let cal = Calendar.current
        let now = Date.now
        func date(_ daysAgo: Int) -> Date {
            cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }
        let courant = changementDoseRecent ?? date(45)
        let entryCourante = DoseChange(dose: doseActuelle, startDate: courant, endDate: nil)

        if nuitsAnalysees == 0 {
            return [entryCourante]
        }

        return [
            entryCourante,
            DoseChange(dose: doseActuelle - 1, startDate: date(75),  endDate: courant),
            DoseChange(dose: doseActuelle - 2, startDate: date(110), endDate: date(75)),
            DoseChange(dose: doseActuelle - 1, startDate: date(140), endDate: date(110)),
        ]
    }
}
