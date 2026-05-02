//
//  AppRouter.swift
//  insulog
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

/// Identifie les onglets racine de la TabView. Sert de tag pour la
/// sélection — utile pour conditionner l'accessoire de tab bar à
/// l'onglet courant.
enum TabId: Hashable, Sendable {
    case accueil
    case journal
    case analyses
    case recherche
}

/// État de navigation partagé pour piloter l'accessoire de tab bar
/// (`tabViewBottomAccessory`) iOS 26.
///
/// Quand l'utilisateur entre dans une page détail du Journal
/// (Repas / Médications / Sport), `inJournalDetail` passe à `true` et
/// l'accessoire — un switcher 3-segments Liquid Glass posé entre les
/// pills de tab — devient visible. `journalSection` reflète la
/// section affichée et permet à l'accessoire de mettre en évidence
/// le bon segment, et inversement à l'utilisateur de basculer entre
/// sections sans push/pop de navigation.
@Observable
@MainActor
final class AppRouter {
    /// Onglet racine actif. Bindé à la sélection de la TabView.
    var selectedTab: TabId = .journal

    /// `true` quand `JournalDetailVue` est sur l'écran. Utilisé pour
    /// activer/désactiver l'accessoire de tab bar via le paramètre
    /// `isEnabled` de `tabViewBottomAccessory`.
    var inJournalDetail: Bool = false

    /// Section actuellement affichée dans `JournalDetailVue`. Tap sur
    /// un segment de l'accessoire écrit ici ; `JournalDetailVue`
    /// observe la valeur et bascule son contenu en conséquence.
    var journalSection: SectionJournal = .repas
}
