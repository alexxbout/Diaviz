//
//  PreferencesAlimentsModeles.swift
//  diaviz
//

import Foundation
import SwiftData

/// Préférences utilisateur portant sur les aliments et l'usage de l'app.
///
/// Ces réglages vivaient dans `UserDefaults`, donc hors du hub SwiftData et
/// hors CloudKit : ils disparaissaient à la désinstallation, sans possibilité
/// de restauration. Ce sont pourtant de vraies décisions de l'utilisateur
/// (renommages, masquages, habitudes de saisie) accumulées à l'usage. Les
/// passer en `@Model` les fait bénéficier de la même synchronisation que le
/// reste des données.
///
/// Mêmes contraintes CloudKit que le reste du hub : aucun
/// `@Attribute(.unique)`, toute propriété stockée optionnelle ou pourvue
/// d'une valeur par défaut.

// MARK: - Aliment CIQUAL personnalisé / masqué

/// Personnalisation d'un aliment du référentiel CIQUAL : nom, emoji, et/ou
/// masquage des suggestions. Une seule ligne par aliment, quelle que soit la
/// combinaison — les trois réglages portent sur le même objet et changent
/// souvent ensemble.
@Model
final class PreferenceAlimentCiqual {

    /// Identifiant de l'aliment dans `ciqual.json`.
    var idCiqual: Int = 0

    /// Nom choisi par l'utilisateur. `nil` → nom d'origine CIQUAL.
    var nomPersonnalise: String?

    /// Emoji choisi par l'utilisateur. `nil` → emoji d'origine (souvent absent).
    var emojiPersonnalise: String?

    /// Masqué des suggestions (recherche et récents).
    var masque: Bool = false

    init(
        idCiqual: Int,
        nomPersonnalise: String? = nil,
        emojiPersonnalise: String? = nil,
        masque: Bool = false
    ) {
        self.idCiqual = idCiqual
        self.nomPersonnalise = nomPersonnalise
        self.emojiPersonnalise = emojiPersonnalise
        self.masque = masque
    }

    /// Ligne devenue inutile — plus aucun réglage actif. Sert à purger
    /// plutôt qu'à accumuler des lignes neutres qui partiraient sur iCloud.
    var estVide: Bool {
        nomPersonnalise == nil && emojiPersonnalise == nil && !masque
    }
}

// MARK: - Aliment récent

/// Un aliment utilisé récemment, avec les habitudes de saisie associées.
///
/// Couvre indifféremment CIQUAL et Open Food Facts via la clé composite
/// (`"ciqual:123"`, `"off:3017620422003"`) déjà utilisée par
/// `ResultatRechercheAliment.id`. Pour un produit OFF, `snapshot` conserve le
/// produit sérialisé : il n'existe aucune base locale où le retrouver.
@Model
final class AlimentRecentEnregistre {

    /// Clé composite de l'aliment.
    var cle: String = ""

    /// Position dans la liste MRU (0 = le plus récent). Un rang explicite
    /// plutôt que l'ordre d'insertion : SwiftData ne garantit aucun ordre de
    /// fetch, et CloudKit encore moins.
    var rang: Int = 0

    /// Dernière quantité saisie, en grammes.
    var quantite: Double?

    /// Taille d'une portion définie par l'utilisateur, en grammes.
    var taillePortion: Double?

    /// Dernier mode de saisie (`ModeQuantiteAliment.rawValue`).
    var modeQuantite: String?

    /// Produit Open Food Facts sérialisé (JSON). `nil` pour un aliment CIQUAL.
    var snapshot: Data?

    init(
        cle: String,
        rang: Int,
        quantite: Double? = nil,
        taillePortion: Double? = nil,
        modeQuantite: String? = nil,
        snapshot: Data? = nil
    ) {
        self.cle = cle
        self.rang = rang
        self.quantite = quantite
        self.taillePortion = taillePortion
        self.modeQuantite = modeQuantite
        self.snapshot = snapshot
    }
}

// MARK: - Contexte de repas normalisé

/// Entrée du référentiel de contextes de repas (« conduire », « stress
/// boulot »…) vers laquelle convergent plusieurs formulations brutes.
@Model
final class ContexteNormaliseEnregistre {

    var identifiant: UUID = UUID()
    var libelle: String = ""
    var emoji: String = "🏷️"

    /// Formulations brutes déjà rattachées. Stockage optionnel puis
    /// accesseur non optionnel : CloudKit échoue au cast sur une collection
    /// non optionnelle, même avec valeur par défaut — même motif que sur
    /// `ProfilUtilisateur`.
    private var _variantes: [String]? = []
    var variantes: [String] {
        get { _variantes ?? [] }
        set { _variantes = newValue }
    }

    /// Position dans la liste (0 = utilisé le plus récemment).
    var rang: Int = 0

    init(
        identifiant: UUID = UUID(),
        libelle: String,
        emoji: String,
        variantes: [String] = [],
        rang: Int = 0
    ) {
        self.identifiant = identifiant
        self.libelle = libelle
        self.emoji = emoji
        self._variantes = variantes
        self.rang = rang
    }
}

// MARK: - Repas « à revoir » masqué

/// Occurrence de repas que l'utilisateur a explicitement écartée de la
/// remontée « Repas à revoir » de l'accueil.
@Model
final class RepasARevoirMasque {

    /// `Repas.id` de l'occurrence masquée.
    var idRepas: UUID = UUID()

    init(idRepas: UUID) {
        self.idRepas = idRepas
    }
}
