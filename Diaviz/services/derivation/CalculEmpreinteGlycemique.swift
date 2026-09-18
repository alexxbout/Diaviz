//
//  CalculEmpreinteGlycemique.swift
//  diaviz
//
//  Created by Alexandre on 18/09/2026.
//

import Foundation

/// Assembleur **pur** de l'empreinte glycémique du jour : découpe la fenêtre
/// métabolique en `nombreAnneaux` tranches égales et dérive, pour chacune,
/// le motif de tirets d'un anneau concentrique — plus la tranche est agitée
/// (loin de la cible, forte variation interne), plus son tiret est
/// fragmenté. Aucune interprétation, aucune IA — une fonction pure des
/// points CGM du jour, recalculable à l'identique.
///
/// Une tranche sans échantillon est **omise**, pas comblée par une valeur
/// inventée (dégradation gracieuse — un trou de couverture CGM doit rester
/// un trou, jamais un anneau fantôme).
///
/// `nonisolated` pour les mêmes raisons que `CalculScoreJournalier` : aucune
/// dépendance SwiftData, testable hors contexte d'acteur.
nonisolated enum CalculEmpreinteGlycemique {

    /// Nombre d'anneaux concentriques — fixe, indépendant du nombre réel
    /// d'échantillons CGM disponibles.
    static let nombreAnneaux = 14

    /// Un anneau concentrique dérivé d'une tranche de temps.
    struct Anneau: Sendable, Equatable, Hashable {
        /// Position de l'anneau, 0 (centre) ..< `nombreAnneaux` (bord).
        let index: Int
        /// Toujours égal à `nombreAnneaux` — porté ici pour que `Anneau`
        /// reste auto-descriptif au moment du rendu (rayon = index / total).
        let total: Int
        /// Glycémie moyenne de la tranche (mg/dL).
        let valeurMoyenne: Int
        /// Agitation [0, 1] : combine l'écart à la cible et la variation
        /// interne de la tranche. Pilote la fragmentation du tiret.
        let agitation: Double
        /// Rotation de départ du motif, en degrés — dérivée de la tranche
        /// (déterministe), pas une constante partagée entre anneaux.
        let rotationDeg: Double
    }

    /// Découpe `fenetre` en `nombreAnneaux` tranches égales. Retourne un
    /// tableau plus court que `nombreAnneaux` si certaines tranches n'ont
    /// aucune donnée.
    static func anneaux(
        depuis lectures: [(date: Date, valeur: Int)],
        fenetre: ClosedRange<Date>
    ) -> [Anneau] {
        let duree = fenetre.upperBound.timeIntervalSince(fenetre.lowerBound)
        guard duree > 0 else { return [] }
        let pas = duree / Double(nombreAnneaux)

        var resultat: [Anneau] = []
        resultat.reserveCapacity(nombreAnneaux)

        for i in 0..<nombreAnneaux {
            let debutCase = fenetre.lowerBound.addingTimeInterval(Double(i) * pas)
            let finCase = fenetre.lowerBound.addingTimeInterval(Double(i + 1) * pas)
            let valeurs = lectures
                .filter { $0.date >= debutCase && $0.date < finCase }
                .map(\.valeur)
            guard !valeurs.isEmpty else { continue }

            let moyenne = Int((Double(valeurs.reduce(0, +)) / Double(valeurs.count)).rounded())
            let dev = min(1, abs(ecartNormalise(moyenne)))
            let etendue = Double((valeurs.max() ?? moyenne) - (valeurs.min() ?? moyenne))
            let etendueNormalisee = min(1, etendue / 60)
            let agitation = min(1, dev * 0.6 + etendueNormalisee * 0.6)
            let rotation = hash(i, moyenne) * 360

            resultat.append(Anneau(
                index: i,
                total: nombreAnneaux,
                valeurMoyenne: moyenne,
                agitation: agitation,
                rotationDeg: rotation
            ))
        }
        return resultat
    }

    // MARK: - Écart à la cible (pur, testable)

    /// Bande cible (mg/dL) — alignée sur `CalculScoreJournalier` (TIR
    /// 70–180). Sert de référence pour l'écart normalisé, pas au calcul du
    /// score lui-même.
    private static let cibleBasse = 70.0
    private static let cibleHaute = 180.0
    private static let cibleMid = (cibleBasse + cibleHaute) / 2   // 125
    private static let clampBas = 40.0
    private static let clampHaut = 300.0

    /// Écart signé à la cible, normalisé dans [-1, 1] : 0 = centre de la
    /// cible, -1 = clamp bas (hypo sévère), +1 = clamp haut (hyper franche).
    static func ecartNormalise(_ valeur: Int) -> Double {
        let v = Double(max(Int(clampBas), min(Int(clampHaut), valeur)))
        if v >= cibleMid {
            return (v - cibleMid) / (clampHaut - cibleMid)
        }
        return (v - cibleMid) / (cibleMid - clampBas)
    }

    /// Hash déterministe [0, 1) — pas de vrai aléatoire : la même tranche
    /// (même index, même valeur) produit toujours la même rotation, donc la
    /// même journée régénère toujours le même dessin.
    private static func hash(_ i: Int, _ valeur: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(valeur) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}
