//
//  CalculFCMax.swift
//  diaviz
//

import Foundation

/// Échantillon de fréquence cardiaque relevé pendant une séance.
nonisolated struct EchantillonFC: Sendable, Equatable {
    let date: Date
    let bpm: Double
}

/// FC max retenue pour convertir une FC moyenne en intensité — **seule**
/// source de la FC max dans l'app (`CalculChargeActive.facteurIntensite`,
/// `intensiteDepuisFC`).
nonisolated struct FCMaxRetenue: Sendable, Equatable {

    enum Origine: Sendable, Equatable {
        /// Plus haut pic soutenu relevé pendant les séances Apple Santé.
        case observee
        /// Valeur théorique fixe, faute d'assez de séances avec FC.
        case theorique
    }

    let bpm: Double
    let origine: Origine
    /// Séances de la fenêtre dont un pic soutenu a pu être mesuré — affiché
    /// avec la valeur, pour qu'on sache sur quoi elle repose.
    let seancesAvecFC: Int

    static let theorique = FCMaxRetenue(bpm: CalculFCMax.fcMaxTheorique, origine: .theorique, seancesAvecFC: 0)
}

/// **FC max personnelle** — la plus haute FC **soutenue** relevée pendant
/// les séances Apple Santé de la dernière année, avec repli sur une valeur
/// théorique tant que les séances ne suffisent pas. Dérivation pure, jamais
/// persistée. Doc : `docs/architecture/Diaviz — Charge active (sport).md` § 5.
///
/// **Pourquoi un pic soutenu, pas un percentile.** Un percentile élevé de
/// tous les échantillons mesure surtout la durée des séances faciles : sur
/// une année de séances modérées, le 99ᵉ percentile tombe loin sous la FC
/// max, qu'on n'atteint que quelques dizaines de secondes en fin d'effort
/// maximal. Le maximum brut, lui, garde n'importe quel artefact capteur.
/// Le pic soutenu (maximum, sur la séance, de la **médiane** d'une fenêtre
/// glissante de 60 s) garde le vrai sommet — tenu plusieurs échantillons
/// d'affilée — et écarte un pic isolé : pour passer la médiane, une valeur
/// doit occuper au moins la moitié de sa fenêtre.
///
/// **Limite.** Une FC max observée est une borne **basse** : si aucune
/// séance n'approche l'effort maximal, elle sous-estime la vraie FC max et
/// les intensités sont surestimées. D'où le minimum de séances, et le
/// nombre de séances affiché avec la valeur.
nonisolated enum CalculFCMax {

    // MARK: Paramètres (registre : docs/architecture/Diaviz — Paramètres à calibrer.md)

    /// Repli tant que la FC max observée n'est pas établie.
    static let fcMaxTheorique = 190.0
    /// Fenêtre de lissage du pic soutenu.
    static let fenetreLissageSecondes: TimeInterval = 60
    /// En dessous, une fenêtre ne prouve rien (échantillonnage épars hors
    /// mode entraînement) : elle est ignorée.
    static let echantillonsMinParFenetre = 3
    /// Séances avec pic mesurable exigées avant de remplacer la valeur
    /// théorique.
    static let seancesMinimum = 10
    /// Pic soutenu au-delà : physiologiquement invraisemblable chez un
    /// adulte, forcément un artefact prolongé — séance écartée.
    static let picPlausibleMax = 220.0
    /// Échantillon hors de cette plage : erreur de mesure, écarté d'emblée.
    static let plageEchantillon: ClosedRange<Double> = 30...250
    /// Profondeur d'historique : la FC max baisse avec l'âge (~1 bpm/an),
    /// une année reste représentative.
    static let historiqueJours = 365

    // MARK: Calcul

    /// Pic soutenu d'une séance : maximum de la médiane de chaque fenêtre de
    /// `fenetreLissageSecondes` démarrant sur un échantillon et contenant au
    /// moins `echantillonsMinParFenetre` échantillons. `nil` si aucune
    /// fenêtre n'en contient assez.
    static func picSoutenu(_ echantillons: [EchantillonFC]) -> Double? {
        let tries = echantillons
            .filter { plageEchantillon.contains($0.bpm) }
            .sorted { $0.date < $1.date }
        var pic: Double?
        var fin = 0
        for debut in tries.indices {
            let limite = tries[debut].date.addingTimeInterval(fenetreLissageSecondes)
            fin = max(fin, debut)
            while fin + 1 < tries.count, tries[fin + 1].date <= limite { fin += 1 }
            let fenetre = tries[debut...fin]
            guard fenetre.count >= echantillonsMinParFenetre else { continue }
            let valeur = mediane(fenetre.map(\.bpm))
            pic = max(pic ?? valeur, valeur)
        }
        return pic
    }

    /// FC max retenue depuis les pics soutenus de chaque séance (`nil` = pas
    /// de pic mesurable, séance non comptée).
    static func retenir(pics: [Double?]) -> FCMaxRetenue {
        let valides = pics.compactMap { $0 }.filter { $0 <= picPlausibleMax }
        guard valides.count >= seancesMinimum, let maximum = valides.max() else {
            return FCMaxRetenue(bpm: fcMaxTheorique, origine: .theorique, seancesAvecFC: valides.count)
        }
        return FCMaxRetenue(bpm: maximum, origine: .observee, seancesAvecFC: valides.count)
    }

    private static func mediane(_ valeurs: [Double]) -> Double {
        let triees = valeurs.sorted()
        let milieu = triees.count / 2
        return triees.count.isMultiple(of: 2) ? (triees[milieu - 1] + triees[milieu]) / 2 : triees[milieu]
    }
}
