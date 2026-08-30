//
//  DetectionRechute.swift
//  diaviz
//

import Foundation

/// Détection d'une **rechute** autour du coucher : un resucrage correctif
/// suivi d'une **nouvelle** hypo dans l'heure — « ma correction n'a pas tenu ».
///
/// Délègue entièrement à B1 (`CalculAnalyseBasale.episodesHypoDetail` +
/// `bilanHypos`) : l'app doit avoir **une seule** définition de la rechute.
/// Deux définitions divergentes du même mot sur deux écrans seraient pires
/// que pas de métrique du tout — l'utilisateur ne saurait plus laquelle il lit.
///
/// `nonisolated` : appelé depuis les calculateurs purs B2/B3.
nonisolated enum DetectionRechute {

    /// Recul (heures) après l'événement pendant lequel on cherche la chaîne
    /// hypo → resucrage correctif → nouvelle hypo. Aligné sur la fenêtre de
    /// sur-correction de B3. La fenêtre large ne crée pas de faux positifs :
    /// `bilanHypos` n'apparie deux épisodes que s'ils sont séparés de moins
    /// de 60 min **et** que le premier porte un resucrage correctif.
    static let reculHeures: Double = 6

    /// `true` si une rechute est observée dans les `reculHeures` suivant
    /// `debut` (prise de lente côté B2, heure de correction côté B3).
    static func rechute(
        lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)],
        de debut: Date,
        seuilHypo: Int
    ) -> Bool {
        let fin = debut.addingTimeInterval(reculHeures * 3600)
        let points = lectures
            .filter { $0.date >= debut && $0.date <= fin }
            .map { (date: $0.date, valeur: $0.valeur) }
        guard !points.isEmpty else { return false }

        let episodes = CalculAnalyseBasale.episodesHypoDetail(points, seuil: seuilHypo)
        // Une rechute suppose au moins deux épisodes : inutile d'aller plus loin.
        guard episodes.count > 1 else { return false }

        var config = ConfigBasale()
        config.seuilHypo = seuilHypo
        let bilan = CalculAnalyseBasale.bilanHypos(
            episodes: episodes,
            resucrages: resucrages.filter { $0.heure >= debut && $0.heure <= fin },
            finEndormissement: debut,
            config: config
        )
        return bilan.rechutes > 0
    }
}
