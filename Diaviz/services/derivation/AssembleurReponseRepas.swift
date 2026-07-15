//
//  AssembleurReponseRepas.swift
//  diaviz
//

import Foundation

/// Assembleur **réponse glycémique post-repas** — dérivation pure, non
/// persistée. À partir des `GlucoseReading` du hub sur la fenêtre T-1h → T+4h
/// autour d'un repas, produit l'`EtatAnalyse` consommé par la row du journal,
/// le détail du repas et le graphe de la journée.
///
/// Remplace `ReponseGlycemiqueServiceMock` (courbes synthétiques). Toujours
/// **factuel** : l'app décrit ce qui s'est passé (pic observé, retour en cible),
/// jamais un conseil de dose.
///
/// Découplé de SwiftData façon `CalculScoreJournalier` / `IOBCalculateur` : le
/// service (`RepasService`) mappe les `@Model` en tuples avant d'appeler ici,
/// pour que ce calcul reste pur et `Sendable`.
enum AssembleurReponseRepas {

    // MARK: - Paramètres

    /// Début de la fenêtre d'observation (T-1h), en secondes relatifs au repas.
    static let debutFenetre: TimeInterval = -3600
    /// Fin de la fenêtre d'observation (T+4h).
    static let finFenetre: TimeInterval = 4 * 3600

    /// Résolution CGM Dexcom (une mesure / 5 min) — sert à estimer la couverture.
    private static let pasEchantillonnage: TimeInterval = 5 * 60

    /// Couverture minimale de la fenêtre post-repas [T0, T+4h] pour qu'une
    /// analyse soit jugée fiable (sinon `donneesManquantes` ou `enAttente`).
    private static let couvertureMinimale = 0.8

    /// Délai de mise à disposition des données Dexcom UE (~3h). Sert à
    /// distinguer « la fenêtre n'est pas encore remplie » (`enAttente`) de
    /// « la fenêtre aurait dû être captée mais ne l'est pas » (`donneesManquantes`).
    private static let delaiCaptureCGM: TimeInterval = 3 * 3600

    /// Borne haute de la cible glycémique (mg/dL). Un « retour en cible » est le
    /// premier point post-pic repassant sous ce seuil.
    private static let cibleHaute = 180.0
    /// Seuil d'hypoglycémie (mg/dL).
    private static let seuilHypo = 70.0

    // MARK: - API

    /// Analyse la réponse glycémique d'un repas.
    ///
    /// - Parameters:
    ///   - heureRepas: instant du repas (T0).
    ///   - aUneInjection: le repas porte-t-il une dose d'insuline ? Sinon la
    ///     réponse n'a pas de sens à analyser (`sansInjection`).
    ///   - echantillons: mesures CGM du hub `(date, valeur mg/dL)`, non filtrées
    ///     (le tri et le découpage se font ici).
    ///   - maintenant: horloge courante — injectée pour rester testable.
    static func analyser(
        heureRepas: Date,
        aUneInjection: Bool,
        echantillons: [(date: Date, valeur: Int)],
        maintenant: Date
    ) -> EtatAnalyse {
        // 1. Sans bolus → pas d'analyse de réponse (choix produit).
        guard aUneInjection else { return .sansInjection }

        // 2. Points de la fenêtre, normalisés en secondes relatives à T0.
        let debut = heureRepas.addingTimeInterval(debutFenetre)
        let fin = heureRepas.addingTimeInterval(finFenetre)
        let points = echantillons
            .filter { $0.date >= debut && $0.date <= fin }
            .sorted { $0.date < $1.date }
            .map { PointCgm(secondesDepuisRepas: $0.date.timeIntervalSince(heureRepas), valeur: Double($0.valeur)) }

        // 3. Couverture de la portion post-repas [T0, T+4h] : c'est elle qui
        //    porte le verdict. Le nombre de points attendu est la fenêtre
        //    divisée par le pas d'échantillonnage.
        let postRepas = points.filter { $0.secondesDepuisRepas >= 0 }
        let attendus = Int(finFenetre / pasEchantillonnage)
        let couverture = attendus > 0 ? Double(postRepas.count) / Double(attendus) : 0

        if couverture >= couvertureMinimale {
            return .disponible(construireReponse(points: points, postRepas: postRepas))
        }

        // 4. Couverture insuffisante : distinguer attente vs données manquantes.
        //    La fenêtre est réputée captable à `fin + delaiCaptureCGM`.
        let disponibleA = fin.addingTimeInterval(delaiCaptureCGM)
        if maintenant < disponibleA {
            let minutesRestantes = Int((disponibleA.timeIntervalSince(maintenant) / 60).rounded(.up))
            return .enAttente(minutesRestantes: max(1, minutesRestantes))
        }
        return .donneesManquantes
    }

    // MARK: - Construction de la réponse

    private static func construireReponse(points: [PointCgm], postRepas: [PointCgm]) -> ReponseGlycemique {
        // Pic = maximum observé en post-repas. `postRepas` est non vide ici
        // (couverture ≥ 80 %), mais on garde un repli défensif.
        let pointPic = postRepas.max { $0.valeur < $1.valeur } ?? points[0]

        // Retour en cible : premier point post-pic repassant sous la cible haute.
        let tempsRetourCible = postRepas.first {
            $0.secondesDepuisRepas > pointPic.secondesDepuisRepas && $0.valeur <= cibleHaute
        }?.secondesDepuisRepas

        return ReponseGlycemique(
            pointsCgm: points,
            verdict: verdict(postRepas: postRepas, pic: pointPic.valeur, tempsRetourCible: tempsRetourCible),
            valeurPic: pointPic.valeur,
            tempsPic: pointPic.secondesDepuisRepas,
            tempsRetourCible: tempsRetourCible
        )
    }

    // MARK: - Verdict (règle « excursion + retour »)
    //
    // Factuel, à partir de la seule courbe observée (cible 70–180) :
    // - mauvais : hypo (<70) OU pic ≥ 250 OU excursion jamais revenue ≤ 180 ;
    // - bon     : aucune hypo ET (pic ≤ 180 OU retour ≤ 180 sous 2h avec pic < 220) ;
    // - moyen   : le reste.
    // Gère les départs en hyper : revenir en cible compte comme un bon résultat.

    private static let retourRapideMax: TimeInterval = 2 * 3600

    private static func verdict(
        postRepas: [PointCgm],
        pic: Double,
        tempsRetourCible: TimeInterval?
    ) -> VerdictGlycemique {
        guard let minPost = postRepas.map(\.valeur).min() else { return .indetermine }

        let hypo = minPost < seuilHypo
        let picTresHaut = pic >= 250
        // « Excursion jamais revenue » : le repas est sorti de cible par le
        // haut et n'y est jamais redescendu dans la fenêtre.
        let jamaisRevenu = pic > cibleHaute && tempsRetourCible == nil

        if hypo || picTresHaut || jamaisRevenu {
            return .mauvais
        }

        if pic <= cibleHaute {
            return .bon
        }
        if let retour = tempsRetourCible, retour <= retourRapideMax, pic < 220 {
            return .bon
        }
        return .moyen
    }
}
