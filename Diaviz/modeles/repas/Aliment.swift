//
//  Aliment.swift
//  diaviz
//
//  Created by Alexandre on 22/04/2026.
//

import Foundation
import SwiftData

/// Un aliment d'un repas, tel qu'enregistré dans le hub : forme déjà résolue
/// (emoji / nom / glucides / dose). Distinct de `EntreeAliment` (saisie, lié à
/// `AlimentCiqual`) et de `AlimentCiqual` (référentiel, hors hub).
@Model
final class Aliment {
    var id: UUID
    var emoji: String
    var nom: String
    var quantite: Int
    var glucides: Int
    var insuline: Double
    /// Photo du produit (Open Food Facts) — `nil` pour un aliment CIQUAL ou
    /// les repas antérieurs à l'ajout du champ (migration légère).
    var imageURL: URL?
    /// Pris pour traiter une hypoglycémie (resucrage) plutôt qu'un aliment de
    /// repas ordinaire. `false` par défaut (migration légère des repas
    /// antérieurs à l'ajout du champ).
    var resucrage: Bool = false
    /// Id CIQUAL source, `nil` pour un produit OFF ou les repas antérieurs à
    /// l'ajout du champ (migration légère). Seul lien vers le référentiel
    /// CIQUAL une fois l'aliment figé dans le hub — sert uniquement à
    /// résoudre un nom/emoji personnalisé (`nomAffiche`/`emojiAffiche`), au
    /// moment de l'affichage plutôt qu'à la saisie : un renommage ultérieur
    /// se reflète alors même sur des repas déjà enregistrés.
    var idCiqualSource: Int?

    init(
        id: UUID = UUID(),
        emoji: String,
        nom: String,
        quantite: Int,
        glucides: Int,
        insuline: Double,
        imageURL: URL? = nil,
        resucrage: Bool = false,
        idCiqualSource: Int? = nil
    ) {
        self.id = id
        self.emoji = emoji
        self.nom = nom
        self.quantite = quantite
        self.glucides = glucides
        self.insuline = insuline
        self.imageURL = imageURL
        self.resucrage = resucrage
        self.idCiqualSource = idCiqualSource
    }

    /// Id CIQUAL utilisable pour résoudre une personnalisation : celui figé à
    /// la saisie, ou — pour les repas enregistrés avant l'ajout du champ —
    /// celui retrouvé par correspondance exacte sur le nom d'origine.
    private var idCiqualResolu: Int? {
        idCiqualSource ?? NomsPersonnalisesService.shared.idCiqual(pourNomOrigine: nom)
    }

    /// Nom à afficher — personnalisé (`NomsPersonnalisesService`) s'il existe
    /// encore pour l'id CIQUAL source, sinon `nom` tel que figé à la saisie.
    /// Ce n'est PAS le nom stocké : `nom` reste le fait historique inchangé
    /// (utilisé par ex. pour la signature de composition de « Repas à
    /// revoir ») ; `nomAffiche` est une résolution à l'affichage uniquement.
    var nomAffiche: String {
        guard let id = idCiqualResolu else { return nom }
        return NomsPersonnalisesService.shared.nomPersonnalise(pour: id) ?? nom
    }

    /// Emoji à afficher — même logique que `nomAffiche`.
    var emojiAffiche: String {
        guard let id = idCiqualResolu else { return emoji }
        return NomsPersonnalisesService.shared.emojiPersonnalise(pour: id) ?? emoji
    }

    /// Aliment générique construit à partir d'une simple quantité de glucides
    /// (g) — pont pour les flux qui n'ont pas encore de recherche aliment
    /// (import HealthKit, édition HealthKit). `ActiviteSportive.alimentsPreSport`
    /// attend une liste d'`Aliment`, pas un `Double` brut.
    static func collationGenerique(glucidesGrammes: Double) -> Aliment {
        Aliment(emoji: "🍬", nom: "Collation", quantite: 0, glucides: Int(glucidesGrammes.rounded()), insuline: 0)
    }
}

/// Un repas enregistré dans le hub. **Fait brut horodaté** (`@Model`) : `heure`
/// absolue + liste d'aliments. La réponse glycémique (`etatAnalyse`) est une
/// **dérivation** calculée depuis le CGM — jamais persistée, d'où `@Transient`.
@Model
final class Repas {
    var id: UUID
    /// Horodatage absolu du repas (clé de tri / découpage).
    var heure: Date

    /// Aliments du repas. Relation cascade : supprimer le repas supprime ses
    /// aliments (ils n'existent pas hors d'un repas).
    @Relationship(deleteRule: .cascade) var aliments: [Aliment]

    /// Insuline rapide encore active au démarrage du repas (unités). Snapshot
    /// figé à la saisie ; `nil` si non calculé (legacy ou pas de bolus récent).
    var iobAuDebut: Double?

    /// Dose unique saisie pour l'ensemble du repas (mode « dose globale »),
    /// quand l'utilisateur connaît les quantités mais ne veut pas ventiler la
    /// dose aliment par aliment. `nil` = mode classique (dose par aliment) —
    /// la valeur EST le flag, pas de booléen séparé à désynchroniser. Dans ce
    /// mode les `Aliment.insuline` valent 0 (pas d'attribution par aliment).
    var doseGlobale: Double?

    /// Dose de correction d'hyperglycémie, distincte de la dose couvrant les
    /// glucides (répond à la glycémie du moment, pas au repas — même exclusion
    /// que `RepasSheet.doseCouvrantGlucides`). `nil` pour les repas enregistrés
    /// avant l'ajout de ce champ : leur `totalInsuline` reste global, une
    /// éventuelle correction potentiellement incluse (proxy, limite connue
    /// pour l'analyse R1 du ratio observé).
    var doseCorrection: Double?

    /// Verdict de la réponse glycémique, **persisté** une fois calculé —
    /// contrairement à `etatAnalyse` qui reste `@Transient` (et porte la
    /// courbe, non stockable). Alimente le mining R1 (analyse du ratio
    /// observé) sur tout l'historique, sans dépendre du CGM en mémoire.
    var verdictPersiste: VerdictGlycemique?

    /// Ratio effectif appliqué (grammes de glucides par unité), figé quand
    /// `verdictPersiste` est renseigné. Calculé sur la dose couvrant les
    /// glucides (`totalInsuline - doseCorrection`), pas sur la dose totale.
    var ratioEffectifPersiste: Double?

    /// Ajustements intentionnels appliqués (sport récent, glycémie basse avant
    /// repas, repas gras…). **Jamais** utilisés pour exclure ce repas d'un
    /// affichage (journal, Repas à revoir) — seulement pour regrouper le
    /// mining R1 à part du ratio de base (`CalculRatioObserve`) et pour les
    /// badges factuels. Vide par défaut (repas sans ajustement).
    var ajustements: [Ajustement] = []

    /// Événement contextuel en texte libre, saisi par l'utilisateur (ex.
    /// « je prends la voiture »). Non structuré : exclu de tout mining
    /// (ratio observé + regroupement composition de Repas à revoir) tant
    /// qu'il n'est pas normalisé, mais affiché tel quel si le verdict est
    /// mauvais. `nil` = pas de contexte particulier.
    var contexteLibre: String?

    /// Libellé normalisé + emoji, résolu en tâche de fond par
    /// `ReferentielContextesService` après l'enregistrement du repas (jamais
    /// à la saisie). `nil` tant que non résolu (ou si la résolution échoue
    /// définitivement) : l'affichage retombe alors sur `contexteLibre` brut.
    /// N'affecte JAMAIS le mining — `AnalyseRatioService`/`CalculRatioObserve`
    /// excluent toujours sur la seule présence de `contexteLibre`.
    var contexteNormalise: String?

    /// `true` si l'utilisateur a explicitement demandé à exclure ce repas de
    /// toute analyse automatique (mining R1, regroupement composition de
    /// Repas à revoir, Repas avec contexte) — même principe que le mode
    /// pause du hub (`PeriodePause`), mais à l'échelle d'un seul repas plutôt
    /// qu'une période entière. Réglable depuis `DetailRepasVue`. Le repas
    /// reste visible partout ailleurs (journal, détail) — seulement ignoré
    /// par les calculs statistiques.
    var exclureDesAnalyses: Bool = false

    /// État du pré-calcul de la réponse glycémique. **Dérivation non persistée**
    /// (`@Transient`) : recalculée à la volée depuis le CGM, et `EtatAnalyse`
    /// embarque une courbe non stockable. Renseignée à l'affichage / en preview.
    @Transient var etatAnalyse: EtatAnalyse?

    init(
        id: UUID = UUID(),
        heure: Date,
        aliments: [Aliment],
        etatAnalyse: EtatAnalyse? = nil,
        iobAuDebut: Double? = nil,
        doseGlobale: Double? = nil,
        doseCorrection: Double? = nil,
        verdictPersiste: VerdictGlycemique? = nil,
        ratioEffectifPersiste: Double? = nil,
        ajustements: [Ajustement] = [],
        contexteLibre: String? = nil,
        contexteNormalise: String? = nil,
        exclureDesAnalyses: Bool = false
    ) {
        self.id = id
        self.heure = heure
        self.aliments = aliments
        self.etatAnalyse = etatAnalyse
        self.iobAuDebut = iobAuDebut
        self.doseGlobale = doseGlobale
        self.doseCorrection = doseCorrection
        self.verdictPersiste = verdictPersiste
        self.ratioEffectifPersiste = ratioEffectifPersiste
        self.ajustements = ajustements
        self.contexteLibre = contexteLibre
        self.contexteNormalise = contexteNormalise
        self.exclureDesAnalyses = exclureDesAnalyses
    }

    var totalGlucides: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }

    /// Total d'insuline du repas : la dose globale quand le repas a été saisi
    /// dans ce mode, sinon la somme des doses par aliment. Tout l'affichage
    /// (journal, détail, ratio) passe par ici et suit automatiquement.
    var totalInsuline: Double {
        doseGlobale ?? aliments.reduce(0) { $0 + $1.insuline }
    }

    /// Somme des ajustements intentionnels (valeurs signées : un ajustement
    /// peut retrancher comme ajouter).
    var totalAjustements: Double {
        ajustements.reduce(0) { $0 + $1.valeur }
    }

    /// Insuline réellement injectée, tous termes confondus — c'est le total
    /// que l'utilisateur a composé sur son stylo.
    ///
    /// `totalInsuline` ne suffit pas : `RepasService.enregistrerDepuisSaisie`
    /// persiste la dose **de base** (`doseGlobale` ou la ventilation par
    /// aliment), les ajustements et la correction partant chacun dans leur
    /// propre champ. Les trois doivent donc être resommés à la lecture.
    ///
    /// Même formule que `RepasSheet.totalInjecte` à la saisie, `max(0, …)`
    /// compris — un ajustement négatif plus gros que la dose de base ne doit
    /// pas produire un total négatif.
    var totalInjecte: Double {
        max(0, totalInsuline + totalAjustements + (doseCorrection ?? 0))
    }

    /// Indique si au moins un aliment a une dose d'insuline associée. Sert à
    /// différencier un repas "logué pour mémoire" d'un repas avec bolus.
    var aUneInjection: Bool {
        totalInsuline > 0
    }

    /// Emoji représentatif du repas : l'aliment le plus contributeur en
    /// glucides (il pilote la réponse glycémique). À défaut, un emoji générique.
    var emojiPrincipal: String {
        aliments.max(by: { $0.glucides < $1.glucides })?.emojiAffiche ?? "🍽"
    }
}
