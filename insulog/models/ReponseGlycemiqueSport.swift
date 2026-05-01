//
//  ReponseGlycemiqueSport.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation

/// Photographie de la réponse glycémique pendant et autour d'une
/// session sportive. Pré-calculé côté backend (à terme) — l'app n'a
/// qu'à afficher.
///
/// Fenêtre d'observation : `[-30min, dureeSession + 30min]` autour de
/// l'activité — assez de marge avant pour voir le point de départ
/// stabilisé, et après pour observer le rebond éventuel post-effort.
///
/// Pendant qu'un repas se mesure en pic+retour, une session sportive
/// se mesure en *delta* sur la durée d'effort (chute, stabilité, ou
/// chute trop brutale). Le verdict est donc différent et calculé par
/// la `MiniCourbeSport` directement — la struct n'embarque que les
/// données brutes.
struct ReponseGlycemiqueSport: Codable, Sendable, Hashable {

    /// Échantillons CGM normalisés autour du début de l'activité. Le
    /// champ temporel utilisé est `secondesDepuisDebut` (négatif
    /// avant le début, positif pendant et après).
    let pointsCgm: [PointCgmSport]

    /// Glycémie au tout début de la session (mg/dL).
    let glycemieDebut: Double

    /// Glycémie à la fin de la session (mg/dL).
    let glycemieFin: Double

    /// Variation pendant l'activité — `glycemieFin - glycemieDebut`.
    /// Pré-calculé pour éviter une soustraction côté UI à chaque
    /// rendu de la mini-courbe.
    let deltaMgDl: Double
}

// MARK: - PointCgmSport

/// Échantillon CGM rattaché à une session sportive. Pendant qu'on a
/// `PointCgm` pour les repas (référencé sur T=instant du repas), le
/// référentiel temporel sport est différent : `t=0` est le **début**
/// de la session, et l'amplitude utile est de l'ordre de
/// [-30min, dureeSession + 30min]. On garde un type dédié plutôt que
/// de faire muter le sens de `secondesDepuisRepas` côté repas.
struct PointCgmSport: Codable, Identifiable, Hashable, Sendable {
    /// ID client pour `ForEach`/`Chart`. Non transmis à l'API.
    var id = UUID()
    /// Décalage par rapport au début de la session (négatif avant,
    /// positif pendant/après).
    let secondesDepuisDebut: TimeInterval
    let valeur: Double

    enum CodingKeys: String, CodingKey {
        case secondesDepuisDebut
        case valeur
    }
}
