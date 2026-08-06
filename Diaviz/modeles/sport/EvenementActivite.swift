//
//  EvenementActivite.swift
//  diaviz
//

import Foundation
import SwiftUI

/// Un événement (correction ou resucrage) rattaché à une activité sportive
/// par corrélation temporelle — jamais par lien stocké, même principe que
/// `ActivitesSportService.reponse(pour:)` pour le CGM (voir doc Eraser S1).
///
/// Value type d'affichage : ne porte jamais un `@Model` directement, pour
/// les mêmes raisons que `ResucrageAffiche` (éviter tout accès à un objet
/// invalidé pendant une animation de liste).
struct EvenementActivite: Identifiable, Hashable {
    enum Nature: Hashable {
        case correction
        case resucrage(IntentionResucrage)
    }

    let id: String
    let date: Date
    let nature: Nature
    let detail: String
    /// `true` si l'événement tombe dans une fenêtre de pause de l'activité —
    /// signal direct pour la frise chronologique (Lot 3).
    let pendantPause: Bool

    var icone: String {
        switch nature {
        case .correction:               "syringe"
        case .resucrage(let intention): intention.icone
        }
    }

    var couleur: Color {
        switch nature {
        case .correction:               .blue
        case .resucrage(let intention): intention.couleur
        }
    }

    var titre: String {
        switch nature {
        case .correction:               "Correction"
        case .resucrage(let intention): intention.rawValue
        }
    }
}
