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
nonisolated struct PreferencesAvancees: Codable, Equatable, Sendable {

    /// Occurrences minimales pour qu'un repas récurrent remonte dans « Repas
    /// à revoir » (`CalculRepasARevoir.occurrencesMinimalesParDefaut` si `nil`).
    ///
    /// **Optionnel volontairement**, pas de valeur par défaut sur un `Int` —
    /// un champ non-optionnel ajouté après coup ferait échouer le décodage
    /// JSON des profils déjà persistés (`ProfilService.charger` retombe alors
    /// sur un profil par défaut **entier**, effaçant ratios/insuline déjà
    /// configurés). `Optional` reste décodable même absent du JSON existant.
    var occurrencesMinimalesRepasARevoir: Int?

    /// Glucides (g) au-delà desquels un dîner est jugé **copieux** et
    /// disqualifie la nuit profonde de l'analyse basale (B1) : un repas très
    /// glucidique s'assimile tard, la glycémie reste belle au coucher puis
    /// monte en pleine nuit — la régression y lirait une basale trop faible.
    ///
    /// `nil` → `ConfigBasale.seuilRepasCopieuxParDefaut`. Optionnel pour la
    /// même raison que ci-dessus (compatibilité des profils déjà persistés).
    var seuilRepasCopieuxNuit: Int?

    /// Durée (h) pendant laquelle la carte « Dernier resucrage » reste
    /// visible sur l'accueil après la prise — passé ce délai, la carte
    /// disparaît (elle reste en revanche **toujours** affichée sur la page
    /// Resucrage elle-même, qui n'a pas cette notion de fenêtre).
    ///
    /// `nil` → `CarteResucrageRecent.fenetreAccueilParDefautHeures`. Optionnel
    /// pour la même raison que ci-dessus (compatibilité des profils déjà
    /// persistés).
    var fenetreAffichageResucrageAccueilHeures: Int?

    /// Quantité (g) pré-remplie par le bouton d'ajout rapide de la sheet
    /// resucrage — enregistre directement un aliment générique « Glucides
    /// rapides » sans passer par la recherche. `nil` →
    /// `SheetNouveauResucrage.glucidesRapidesParDefaut` (15g, dose standard
    /// de resucrage). Optionnel pour la même raison que ci-dessus.
    var glucidesResucrageRapideParDefaut: Int?

    /// Overlay des stades de sommeil HealthKit sur la courbe nocturne (vue
    /// « Par nuit » de l'analyse du coucher). `nil` → désactivé par défaut
    /// (`false`) : l'accès HealthKit au sommeil n'est demandé qu'à
    /// l'activation explicite de ce réglage, jamais au boot. Optionnel pour
    /// la même raison que ci-dessus (compatibilité des profils déjà
    /// persistés).
    var overlaySommeilActive: Bool?

    /// Cartes de courbe (réponse d'un repas ou d'une séance) dans la pile
    /// « Nouvelles tendances ». `nil` → affichées. Optionnel pour la même
    /// raison que ci-dessus.
    var cartesCourbesInsightsActives: Bool?

    /// Statuts imposés à la main sur des nuits passées (tendance basale), par
    /// jour du soir de la nuit (`ClassementManuelNuit.cle`). `nil` → aucun.
    /// Optionnel pour la même raison que ci-dessus.
    var classementsNuits: [String: ClassementManuelNuit]?

    init(occurrencesMinimalesRepasARevoir: Int? = nil,
         seuilRepasCopieuxNuit: Int? = nil,
         fenetreAffichageResucrageAccueilHeures: Int? = nil,
         glucidesResucrageRapideParDefaut: Int? = nil,
         overlaySommeilActive: Bool? = nil,
         cartesCourbesInsightsActives: Bool? = nil,
         classementsNuits: [String: ClassementManuelNuit]? = nil) {
        self.classementsNuits = classementsNuits
        self.occurrencesMinimalesRepasARevoir = occurrencesMinimalesRepasARevoir
        self.seuilRepasCopieuxNuit = seuilRepasCopieuxNuit
        self.fenetreAffichageResucrageAccueilHeures = fenetreAffichageResucrageAccueilHeures
        self.glucidesResucrageRapideParDefaut = glucidesResucrageRapideParDefaut
        self.overlaySommeilActive = overlaySommeilActive
        self.cartesCourbesInsightsActives = cartesCourbesInsightsActives
    }
}
