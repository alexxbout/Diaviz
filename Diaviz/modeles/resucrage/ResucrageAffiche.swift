//
//  ResucrageAffiche.swift
//  diaviz
//

import Foundation

/// Snapshot **value type** d'un `Resucrage` pour l'affichage en liste.
///
/// Les vues ne consomment jamais le `@Model` directement : supprimer un
/// `Resucrage` invalide l'objet *et* ses `Aliment` liés (relation
/// `.cascade`), alors que la row concernée est encore vivante le temps de
/// l'animation de suppression. Toute lecture de propriété pendant cette
/// fenêtre crashe (« This model instance was invalidated »). Un snapshet
/// figé au moment du fetch supprime la classe de bug entière — même
/// découplage que `RepasService`, qui mappe ses `@Model` avant de les
/// passer aux calculateurs purs.
struct ResucrageAffiche: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let intention: IntentionResucrage
    let glucidesTotal: Int
    /// Nom du seul aliment quand il n'y en a qu'un — sinon `nil` (la vue
    /// affiche « N aliments » à partir de `nombreAliments`).
    let nomAlimentUnique: String?
    let nombreAliments: Int
    let glycemieCible: Double?
}

extension Resucrage {
    /// Fige l'état courant pour l'affichage. Appelé côté service, sur des
    /// objets encore valides.
    var affichage: ResucrageAffiche {
        ResucrageAffiche(
            id: id,
            date: date,
            intention: intention,
            glucidesTotal: glucidesTotal,
            nomAlimentUnique: aliments.count == 1 ? aliments[0].nomAffiche : nil,
            nombreAliments: aliments.count,
            glycemieCible: glycemieCible
        )
    }
}
