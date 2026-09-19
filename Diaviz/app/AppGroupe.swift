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

enum AppGroupe {
    static let identifiant = "group.fr.al3xdre.diaviz.widget"
}

/// Identifiant de kind du widget "empreinte glycémique du jour" — partagé
/// entre l'app (reload ciblé) et l'extension (déclaration du `Widget`).
enum EmpreinteWidgetKind {
    static let identifiant = "EmpreinteGlycemiqueWidget"
}
