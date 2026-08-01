//
//  PreferencesAvancees.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Préférences avancées du profil — repliées par défaut dans la sheet,
/// car peu de gens les modifient.
///
/// `margeAlerteDose` : écart toléré (en unités) entre la dose saisie
/// par l'utilisateur et la dose suggérée par son ratio avant de
/// déclencher un avertissement « cette dose s'écarte de votre ratio ».
/// L'app n'empêche jamais la saisie ; elle informe seulement.
struct PreferencesAvancees: Codable, Equatable, Sendable {
    var margeAlerteDose: Double

    /// Occurrences minimales pour qu'un repas récurrent remonte dans « Repas
    /// à revoir » (`CalculRepasARevoir.occurrencesMinimalesParDefaut` si `nil`).
    ///
    /// **Optionnel volontairement**, pas de valeur par défaut sur un `Int` —
    /// un champ non-optionnel ajouté après coup ferait échouer le décodage
    /// JSON des profils déjà persistés (`ProfilService.charger` retombe alors
    /// sur un profil par défaut **entier**, effaçant ratios/insuline déjà
    /// configurés). `Optional` reste décodable même absent du JSON existant.
    var occurrencesMinimalesRepasARevoir: Int?

    init(margeAlerteDose: Double = 1, occurrencesMinimalesRepasARevoir: Int? = nil) {
        self.margeAlerteDose = margeAlerteDose
        self.occurrencesMinimalesRepasARevoir = occurrencesMinimalesRepasARevoir
    }
}
