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
nonisolated final class Aliment {
    var id: UUID = UUID()
    var emoji: String = ""
    var nom: String = ""
    var quantite: Int = 0
    var glucides: Int = 0
    var insuline: Double = 0
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
    /// Taille (g) de la portion si l'aliment a été saisi en portions, `nil`
    /// s'il l'a été en grammes ou avant l'ajout du champ. Rouvre le repas dans
    /// le même mode de saisie.
    var taillePortion: Double?
    /// Code-barres du produit Open Food Facts, `nil` pour un aliment CIQUAL ou
    /// les repas antérieurs à l'ajout du champ. Retrouve à la modification du
    /// repas la portion et les corrections propres à ce produit.
    var codeProduitOFF: String?

    /// Inverses des trois relations `@Relationship(deleteRule: .cascade)`
    /// possibles vers cet `Aliment` (`Repas.aliments`, `Resucrage.aliments`,
    /// `ActiviteSportive.alimentsPreSport`) — CloudKit exige que toute
    /// relation ait un inverse déclaré, sinon le container échoue à
    /// l'initialisation (constaté à l'exécution, invisible à la compilation).
    /// Un `Aliment` n'appartient jamais qu'à un seul des trois à la fois ;
    /// les deux autres restent `nil`. Jamais lus directement par le code de
    /// l'app (uniquement là pour satisfaire la contrainte du schéma).
    ///
    /// ⚠️ Effet de bord une fois l'inverse déclaré : SwiftData applique la
    /// propriété « un seul parent à la fois » même sur des objets construits
    /// hors `ModelContext`. Réutiliser la **même instance** `Aliment` dans
    /// plusieurs `Repas`/`Resucrage`/`ActiviteSportive` (raccourci de fixture
    /// pratique avant l'ajout de l'inverse) la « vole » silencieusement au
    /// dernier parent assigné — les précédents se retrouvent avec `aliments`
    /// vide. Toujours construire une instance `Aliment` **distincte** par
    /// parent, même à contenu identique (reflète d'ailleurs la vraie donnée :
    /// deux repas identiques ont chacun leurs propres lignes `Aliment` en
    /// production, jamais une ligne partagée).
    var repasParent: Repas?
    var resucrageParent: Resucrage?
    var activiteSportiveParent: ActiviteSportive?

    init(
        id: UUID = UUID(),
        emoji: String,
        nom: String,
        quantite: Int,
        glucides: Int,
        insuline: Double,
        imageURL: URL? = nil,
        resucrage: Bool = false,
        idCiqualSource: Int? = nil,
        taillePortion: Double? = nil,
        codeProduitOFF: String? = nil
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
        self.taillePortion = taillePortion
        self.codeProduitOFF = codeProduitOFF
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
nonisolated final class Repas {
    var id: UUID = UUID()
    /// Horodatage absolu du repas (clé de tri / découpage).
    var heure: Date = Date.distantPast

    /// Stockage réel de la relation — **optionnel**, exigé par CloudKit pour
    /// toute relation (y compris à plusieurs) : la synchro ne garantit pas
    /// que le graphe entier arrive d'un coup, un objet peut être là sans que
    /// sa relation le soit encore, ce qui se traduit par `nil`. `aliments`
    /// ci-dessous en donne une vue non-optionnelle, seule utilisée par le
    /// reste du code (aucun appelant ne touche `_aliments` directement).
    @Relationship(deleteRule: .cascade, inverse: \Aliment.repasParent) var _aliments: [Aliment]? = []

    /// Aliments du repas. Relation cascade : supprimer le repas supprime ses
    /// aliments (ils n'existent pas hors d'un repas).
    var aliments: [Aliment] {
        get { _aliments ?? [] }
        set { _aliments = newValue }
    }

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

    /// Cause du verdict `.mauvais`, figée en même temps que lui — `nil` pour
    /// tout autre verdict, et pour les repas annotés avant l'ajout du champ
    /// (hors fenêtre de ré-annotation de 45 jours, ils ne repasseront jamais
    /// par l'assembleur). Optionnel sans contrainte : compatible CloudKit et
    /// sans migration.
    var raisonMauvaisPersistee: RaisonMauvaisVerdict?

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

    /// Événements de vie attachés au repas (« 🚘 Voiture », « 🍽️ Restaurant »),
    /// éditables après coup depuis `SheetEvenementsRepas`. Vide par défaut.
    ///
    /// Un repas qui en porte au moins un est **exclu du mining du ratio** :
    /// une circonstance particulière rend la dose non représentative du ratio
    /// de base. Conséquence assumée — taguer un ancien repas le retire
    /// rétroactivement de l'analyse, retirer son dernier événement l'y remet.
    var evenements: [EvenementRepas] = []

    /// Ancien champ texte libre unique, conservé pour les repas enregistrés
    /// avant `evenements` — jamais réécrit, seulement lu par
    /// `evenementsAffiches`. La première édition d'un repas legacy le
    /// matérialise dans `evenements` et remet ce champ à `nil`.
    var contexteLibre: String?

    /// Libellé normalisé + emoji de l'ancien `contexteLibre`, résolu en tâche
    /// de fond après enregistrement. Même statut legacy que ci-dessus.
    var contexteNormalise: String?

    /// `true` si l'utilisateur a explicitement demandé à exclure ce repas de
    /// toute analyse automatique (mining R1, regroupement composition de
    /// Repas à revoir, Repas avec contexte) — même principe que le mode
    /// pause du hub (`PeriodePause`), mais à l'échelle d'un seul repas plutôt
    /// qu'une période entière. Réglable depuis `DetailRepasVue`. Le repas
    /// reste visible partout ailleurs (journal, détail) — seulement ignoré
    /// par les calculs statistiques.
    var exclureDesAnalyses: Bool = false

    /// Date de la dernière modification après enregistrement, `nil` pour un
    /// repas jamais retouché. Signale qu'il a été réécrit après coup : une
    /// dose corrigée une fois la courbe connue pèse sur le ratio observé.
    var dateModification: Date?

    /// Moment de la journée choisi à la main (`SectionRepas.rawValue`), `nil`
    /// pour le classement automatique selon l'heure et les horaires du profil.
    var momentChoisi: String?

    /// Moment du repas : le choix manuel prime. **Seule lecture à utiliser**
    /// pour ranger un repas ou lui associer un ratio.
    nonisolated func section(horaires: HorairesRepas) -> SectionRepas {
        momentChoisi.flatMap(SectionRepas.init(rawValue:)) ?? SectionRepas(heure: heure, horaires: horaires)
    }

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
        raisonMauvaisPersistee: RaisonMauvaisVerdict? = nil,
        ratioEffectifPersiste: Double? = nil,
        ajustements: [Ajustement] = [],
        evenements: [EvenementRepas] = [],
        contexteLibre: String? = nil,
        contexteNormalise: String? = nil,
        exclureDesAnalyses: Bool = false
    ) {
        self.id = id
        self.heure = heure
        self._aliments = aliments
        self.etatAnalyse = etatAnalyse
        self.iobAuDebut = iobAuDebut
        self.doseGlobale = doseGlobale
        self.doseCorrection = doseCorrection
        self.verdictPersiste = verdictPersiste
        self.raisonMauvaisPersistee = raisonMauvaisPersistee
        self.ratioEffectifPersiste = ratioEffectifPersiste
        self.ajustements = ajustements
        self.evenements = evenements
        self.contexteLibre = contexteLibre
        self.contexteNormalise = contexteNormalise
        self.exclureDesAnalyses = exclureDesAnalyses
    }

    var totalGlucides: Int {
        aliments.reduce(0) { $0 + $1.glucides }
    }

    // MARK: - Événements

    /// Événements à afficher, `evenements` complété par une reconstruction des
    /// repas legacy — ceux enregistrés quand le contexte était un champ texte
    /// unique. Pas de migration en base : un repas ancien n'est réécrit que si
    /// l'utilisateur l'édite (voir `remplacerEvenements(_:)`), ce qui évite de
    /// toucher tout l'historique au premier lancement.
    ///
    /// L'ancien `contexteNormalise` est un affichage déjà combiné
    /// (« 🚘 Voiture ») : impossible d'en réextraire proprement l'emoji, donc
    /// l'événement reconstruit porte le tout en `libelle` et un emoji vide —
    /// `EvenementRepas.affichage` gère ce cas.
    var evenementsAffiches: [EvenementRepas] {
        if !evenements.isEmpty { return evenements }
        guard let contexteLibre else { return [] }
        return [EvenementRepas(
            libelle: contexteNormalise ?? contexteLibre,
            emoji: "",
            texteBrut: contexteLibre
        )]
    }

    /// `true` dès qu'une circonstance particulière est déclarée sur ce repas.
    /// C'est ce prédicat qui l'exclut du mining du ratio — jamais un test
    /// direct sur `contexteLibre`, qui raterait les repas récents.
    var aUnEvenement: Bool {
        !evenements.isEmpty || contexteLibre != nil
    }

    /// Écrit la nouvelle liste d'événements et **solde le champ legacy** :
    /// une fois le repas édité, `contexteLibre` n'a plus à être consulté, et
    /// le laisser renseigné ferait réapparaître l'ancien contexte si
    /// l'utilisateur retire tous les événements.
    func remplacerEvenements(_ nouveaux: [EvenementRepas]) {
        evenements = nouveaux
        contexteLibre = nil
        contexteNormalise = nil
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
