//
//  AppGroupe.swift
//  diaviz
//
//  Identifiant App Group partagé entre l'app et l'extension widget
//  (`DiavizSportWidgetExtension`) pour l'échange de l'empreinte glycémique
//  du jour via UserDefaults(suiteName:). Capability à ajouter dans Xcode
//  (Signing & Capabilities → App Groups) sur les deux cibles avant de
//  pouvoir builder.
//

nonisolated enum AppGroupe {
    #if DEMO
    /// App « Diaviz Démo » : groupe distinct, pour que le widget démo ne lise
    /// jamais l'empreinte de la vraie app (ni l'inverse).
    static let identifiant = "group.fr.al3xdre.diaviz.demo.widget"
    #else
    static let identifiant = "group.fr.al3xdre.diaviz.widget"
    #endif
}

/// Identifiant de kind du widget "empreinte glycémique du jour" — partagé
/// entre l'app (reload ciblé) et l'extension (déclaration du `Widget`).
nonisolated enum EmpreinteWidgetKind {
    static let identifiant = "EmpreinteGlycemiqueWidget"
}
