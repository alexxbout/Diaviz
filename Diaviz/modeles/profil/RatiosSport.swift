//
//  RatiosSport.swift
//  diaviz
//

import Foundation

/// Ratios insuline / glucides à appliquer **après une activité sportive**,
/// distincts par type de sport.
///
/// Chaque valeur est exprimée comme les ratios du profil : grammes de
/// glucides couverts par 1 unité d'insuline rapide (« 1u / Xg »). Un ratio
/// plus élevé que le ratio de base traduit la sensibilité accrue à
/// l'insuline qui suit un effort d'endurance ; la musculation peut au
/// contraire demander un ratio plus bas (glycémie qui monte).
///
/// Tous les types sont **optionnels** : `nil` = pas de ratio spécifique
/// pour ce sport, on retombe alors sur le ratio du moment de la journée.
/// Aucun réglage n'est requis pour que l'app fonctionne.
///
/// « Un hub, des dérivations » : ces valeurs sont des **références
/// d'analyse** saisies par l'utilisateur (typiquement dictées par son
/// médecin), jamais un calcul de dose fait par l'app.
struct RatiosSport: Codable, Equatable, Sendable {

    /// Ratio par type de sport, en grammes couverts par 1u. Stocké par
    /// `rawValue` de `TypeSport` (et non par l'enum directement) pour que
    /// l'ajout d'un futur type de sport ne casse pas le décodage des
    /// profils déjà persistés.
    var parType: [String: Double]

    /// Durée après la fin d'une séance pendant laquelle le ratio sport
    /// s'applique, en heures. Au-delà, le ratio du moment reprend.
    var fenetreEffetHeures: Double

    /// Valeur par défaut de la fenêtre — 3h, ordre de grandeur usuel de
    /// la sensibilité post-effort.
    static let fenetreParDefaut: Double = 3

    init(parType: [String: Double] = [:], fenetreEffetHeures: Double = RatiosSport.fenetreParDefaut) {
        self.parType = parType
        self.fenetreEffetHeures = fenetreEffetHeures
    }

    /// Ratio configuré pour un type de sport, ou `nil` si l'utilisateur
    /// n'en a pas défini (→ l'appelant retombe sur le ratio du moment).
    func ratio(pour type: TypeSport) -> Double? {
        parType[type.rawValue]
    }

    /// Définit (ou efface, avec `nil`) le ratio d'un type de sport.
    mutating func definir(_ valeur: Double?, pour type: TypeSport) {
        if let valeur {
            parType[type.rawValue] = valeur
        } else {
            parType.removeValue(forKey: type.rawValue)
        }
    }

    /// `true` si au moins un type de sport a un ratio renseigné — sert au
    /// résumé affiché sur la row « Ratios » de l'index du profil.
    var aAuMoinsUnRatio: Bool { !parType.isEmpty }
}
