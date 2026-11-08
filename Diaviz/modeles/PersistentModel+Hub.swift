//
//  PersistentModel+Hub.swift
//  diaviz
//

import SwiftData

nonisolated extension PersistentModel {

    /// `false` dès que l'objet est supprimé. SwiftUI peut redessiner une ligne
    /// une dernière fois entre la suppression et son retrait de la liste : lire
    /// alors certains champs de l'objet supprimé fait planter l'app. Toute vue
    /// qui détient un `@Model` supprimable doit vérifier ceci avant de le lire.
    var estEncoreDansLeHub: Bool {
        modelContext != nil && !isDeleted
    }
}
