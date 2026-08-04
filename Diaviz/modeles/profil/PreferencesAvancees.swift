//
//  PreferencesAvancees.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Réglages fins du profil qui n'ont pas leur place dans une section
/// dédiée. Le nom de type (et la clé JSON `preferencesAvancees` côté
/// `ProfilUtilisateur`) est conservé tel quel : le renommer ferait échouer
/// le décodage des profils déjà persistés.
///
/// L'ancien champ `margeAlerteDose` a été retiré — il n'était lu nulle
/// part dans l'app (écrit dans le profil, jamais consommé), et la section
/// « Préférences avancées » qui l'exposait ne contenait que lui.
/// Retirer une propriété d'un `Codable` est sûr : les clés en trop du JSON
/// existant sont ignorées au décodage.
struct PreferencesAvancees: Codable, Equatable, Sendable {

    /// Occurrences minimales pour qu'un repas récurrent remonte dans « Repas
    /// à revoir » (`CalculRepasARevoir.occurrencesMinimalesParDefaut` si `nil`).
    ///
    /// **Optionnel volontairement**, pas de valeur par défaut sur un `Int` —
    /// un champ non-optionnel ajouté après coup ferait échouer le décodage
    /// JSON des profils déjà persistés (`ProfilService.charger` retombe alors
    /// sur un profil par défaut **entier**, effaçant ratios/insuline déjà
    /// configurés). `Optional` reste décodable même absent du JSON existant.
    var occurrencesMinimalesRepasARevoir: Int?

    init(occurrencesMinimalesRepasARevoir: Int? = nil) {
        self.occurrencesMinimalesRepasARevoir = occurrencesMinimalesRepasARevoir
    }
}
