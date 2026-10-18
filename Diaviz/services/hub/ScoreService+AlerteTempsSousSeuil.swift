//
//  ScoreService+AlerteTempsSousSeuil.swift
//  diaviz
//

import CryptoKit
import Foundation

/// Alerte « temps sous 70 mg/dL » pour la pile d'insights de l'accueil —
/// vit sur `ScoreService` car elle réutilise tels quels ses jours terminés
/// (même découpage 06h→06h, même couverture minimale) : aucun second calcul
/// du CGM, donc aucun écart possible avec les chiffres du score.
extension ScoreService {

    /// Temps sous 70 mg/dL (% du jour) des `nombreJours` derniers jours
    /// **terminés**, du plus ancien (J-3) au plus récent (J-1). `nil` pour un
    /// jour sans score consolidé (couverture insuffisante).
    var tempsSousSeuilDerniersJours: [Double?] {
        let cal = Calendar.current
        return (1...CalculAlerteTempsSousSeuil.nombreJours).reversed().map { decalage in
            guard let jour = cal.date(byAdding: .day, value: -decalage, to: jourCourant),
                  let score = score(pour: jour) else { return nil }
            // Sous 70 = niveau 1 (54–69) + niveau 2 (< 54), comme la barre AGP.
            return score.faits.tbrLevel1 + score.faits.tbrLevel2
        }
    }

    /// Observation « temps sous 70 mg/dL » — `nil` tant que la moyenne des
    /// 3 derniers jours terminés reste sous 3 %, ou faute de recul. Toujours
    /// en tête de pile (`AccueilVue`).
    ///
    /// `id` **dérivé du contenu** (moyenne au dixième), pas aléatoire — même
    /// principe que les autres insights : supprimer l'alerte la masque tant
    /// que le chiffre affiché ne change pas, elle revient dès qu'il bouge.
    var insightTempsSousSeuil: Insight? {
        guard let resultat = CalculAlerteTempsSousSeuil.evaluer(parJour: tempsSousSeuilDerniersJours) else {
            return nil
        }
        let moyenne = resultat.moyenne.formatted(.number.precision(.fractionLength(1)))
        let joursExploitables = resultat.parJour.compactMap { $0 }.count
        let seuil = Int(CalculAlerteTempsSousSeuil.seuilPourcent)

        return Insight(
            id: Self.identifiantStable("tempsSousSeuil|\(moyenne)"),
            categorie: .alerte,
            titre: "Temps sous 70 mg/dL",
            // Espace insécable avant « % » : sans elle, le pourcentage pouvait
            // passer seul à la ligne.
            message: "Moyenne sur \(joursExploitables) jours, seuil de \(seuil)\u{00A0}%",
            microVisuel: .grandNombreEtJours(
                valeur: "\(moyenne)\u{00A0}%",
                jours: resultat.parJour,
                seuil: CalculAlerteTempsSousSeuil.seuilPourcent
            ),
            lienAnalyse: nil
        )
    }

    /// UUID stable dérivé d'une chaîne (SHA-256 tronqué à 16 octets) — jamais
    /// `String.hashValue`, qui change à chaque lancement et casserait la
    /// persistance des insights supprimés.
    private static func identifiantStable(_ chaine: String) -> UUID {
        let octets = Array(SHA256.hash(data: Data(chaine.utf8)).prefix(16))
        return UUID(uuid: (
            octets[0], octets[1], octets[2], octets[3],
            octets[4], octets[5], octets[6], octets[7],
            octets[8], octets[9], octets[10], octets[11],
            octets[12], octets[13], octets[14], octets[15]
        ))
    }
}
