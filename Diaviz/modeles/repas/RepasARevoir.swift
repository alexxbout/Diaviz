//
//  RepasARevoir.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import Foundation
import SwiftUI

// Capitalise uniquement la première lettre — `String.capitalized` capitalise
// CHAQUE mot et transformerait « lun. 12 juin » en « Lun. 12 Juin ».
private extension String {
    var capitalizedFirstLetter: String {
        guard let premiere = first else { return self }
        return String(premiere).uppercased() + dropFirst()
    }
}

// MARK: - Point de courbe

/// Point unique d'une courbe de réponse glycémique post-repas, indexé
/// en **minutes** depuis T0 (instant du repas). Granularité ~15 min
/// sur 3h, avec des points intermédiaires possibles pour caler
/// exactement les pics (qui ne tombent pas toujours sur la grille).
struct PointCourbeRepas: Identifiable, Sendable {
    let id = UUID()
    /// Minutes depuis T0 (0 = instant du repas).
    let minutes: Int
    /// Glycémie en mg/dL.
    let glycemie: Double
}

// MARK: - Événement sur la courbe

/// Un fait du hub survenu **pendant** la fenêtre post-repas, superposé à la
/// courbe pour expliquer sa forme : bolus du repas, correction, lente, autre
/// repas, séance de sport.
///
/// Positionné en minutes depuis T0 (instant du repas), comme
/// `PointCourbeRepas` — la carte n'a donc aucune date à manipuler.
struct EvenementCourbe: Identifiable, Sendable {

    /// Nature du fait — pilote la couleur, le symbole et le rendu (marqueur
    /// ponctuel vs bande de durée pour le sport).
    enum Genre: Sendable {
        /// Bolus du repas lui-même, à T0.
        case bolusRepas
        /// Correction rapide hors repas pendant la fenêtre.
        case correction
        /// Injection d'insuline lente tombant dans la fenêtre.
        case lente
        /// Autre repas pris pendant la fenêtre (en-cas, resucrage…).
        case repas
        /// Séance sportive chevauchant la fenêtre — seul genre à avoir une
        /// durée, rendu en bande de fond.
        case sport
    }

    let id = UUID()
    let genre: Genre
    /// Minutes depuis T0 du repas analysé.
    let minutes: Int
    /// Durée en minutes — renseignée pour le sport uniquement, `nil` pour les
    /// faits ponctuels.
    let dureeMinutes: Int?
    /// Libellé compact affiché en légende sous le graphe (« 5,5 u », « Course
    /// 45 min »).
    let libelle: String

    init(genre: Genre, minutes: Int, dureeMinutes: Int? = nil, libelle: String) {
        self.genre = genre
        self.minutes = minutes
        self.dureeMinutes = dureeMinutes
        self.libelle = libelle
    }

    /// Couleur sémantique — alignée sur `TypeInsuline.couleur` pour les
    /// injections, afin que le violet « bolus repas » ou le bleu « lente »
    /// veuillent dire la même chose ici et dans l'onglet Médications.
    var couleur: Color {
        switch genre {
        case .bolusRepas: .purple
        case .correction: .orange
        case .lente:      .blue
        case .repas:      .pink
        case .sport:      .green
        }
    }

    /// SF Symbol du marqueur, repris des icônes déjà utilisées par domaine.
    var symbole: String {
        switch genre {
        case .bolusRepas, .correction, .lente: "syringe.fill"
        case .repas:                            "fork.knife"
        case .sport:                            "figure.run"
        }
    }
}

// MARK: - Badge d'ajustement

/// Un badge d'ajustement affichable sur la carte — porte sa catégorie pour
/// que la vue applique la bonne couleur (bleu pour le sport, violet pour les
/// autres raisons). Le contexte libre (orange) est un champ séparé
/// (`RepasARevoir.contexteAffiche`), pas structuré de la même façon.
struct BadgeAjustement: Identifiable {
    let id = UUID()
    let libelle: String
    let estSport: Bool
}

// MARK: - Occurrence passée

/// Une occurrence antérieure du même repas, avec sa courbe **et son
/// verdict**.
///
/// Le verdict est porté ici parce que le nuage gris uniforme d'avant était
/// trompeur : une occurrence passée en hypo à 45 se dessinait exactement
/// comme une occurrence parfaite. Un plat raté 3 fois sur 3 était donc
/// visuellement identique à un plat raté 1 fois sur 3, alors que c'est la
/// distinction la plus utile de la carte — l'une appelle une remise en
/// question du ratio, l'autre suggère un facteur ponctuel.
struct OccurrencePassee: Identifiable {
    let id = UUID()
    let points: [PointCourbeRepas]
    /// `true` si le verdict de cette occurrence était `.mauvais`.
    let horsCible: Bool

    init(points: [PointCourbeRepas], horsCible: Bool = false) {
        self.points = points
        self.horsCible = horsCible
    }
}

// MARK: - RepasARevoir

/// Repas signalé comme « à revoir » sur l'accueil : au moins un
/// aliment a un flag glucides incertains et la réponse glycémique
/// est sortie de cible, hors fenêtre de sport.
///
/// Le modèle porte **toutes** les courbes des occurrences passées
/// (au lieu d'une seule courbe moyenne) — ça permet à la carte de
/// montrer visuellement la **dispersion** des réponses : courbes
/// regroupées = repas prévisible, courbes étalées = repas chaotique.
struct RepasARevoir: Identifiable {
    let id = UUID()

    /// Horizon d'affichage des courbes/événements — 4h post-repas, alignée
    /// sur `AssembleurReponseRepas.finFenetre` et `CalculRepasARevoir.fenetreEvenementsMinutes`.
    /// Domaine X partagé par `CarteRepasARevoir` et `LigneRepasARevoir`.
    static let fenetreAffichageMinutes = 240

    /// Aliments du repas. L'aliment le plus glucidique pilote l'emoji
    /// et le nom affichés en titre de la carte.
    let aliments: [Aliment]

    /// Nombre total de fois où ce repas (composition équivalente) a
    /// été enregistré dans l'historique. Compte la dernière fois
    /// incluse — `occurrencesPassees.count + 1` doit être égal
    /// à cette valeur.
    let nombreOccurrences: Int

    /// Toutes les occurrences passées **sauf** la dernière, avec leur
    /// verdict. Rendues en gris discret dans le mini-chart pour donner une
    /// impression de nuage / dispersion — sauf celles hors cible, teintées
    /// de rouge pour rester distinguables. Si le tableau est vide (un seul
    /// enregistrement total), seule la courbe colorée « dernière fois »
    /// apparaît.
    let occurrencesPassees: [OccurrencePassee]

    /// Courbe de la dernière occurrence — celle qui motive le
    /// « à revoir ». Affichée en trait plein dans la couleur de sévérité.
    let pointsDerniereFois: [PointCourbeRepas]

    /// Minutes depuis T0 de l'événement principal (pic max ou minimum
    /// en cas d'hypo) sur la courbe « dernière fois ».
    let evenementMinutes: Int

    /// Valeur en mg/dL de l'événement principal.
    let evenementValeur: Double

    /// `true` si l'événement principal est une hypo (< 70 mg/dL) plutôt
    /// qu'un pic en hyper. Pilote le triangle ▼ et le libellé « Hypo ».
    let estHypo: Bool

    /// Fourchette de glucides déclarés sur toutes les occurrences de ce
    /// repas — l'écart reflète l'incertitude liée aux aliments estimés.
    let glucidesMin: Int
    let glucidesMax: Int

    /// Libellé du moment (« Déjeuner »…) du **dernier** repas du groupe —
    /// affiché en badge. Jamais utilisé pour exclure la carte de l'affichage.
    let libelleSection: String

    /// Badges des raisons d'ajustement présentes sur le dernier repas
    /// (« Sport récent · Course à pied », « Repas gras »…) — un badge par
    /// raison, affiché systématiquement (bon, moyen ou mauvais verdict).
    let badgesAjustements: [BadgeAjustement]

    /// Événement contextuel en texte libre (`Repas.contexteLibre`), affiché
    /// tel quel — porté par les cartes de « Repas avec contexte » (occurrence
    /// unique, `contexteLibre` exclut ce repas de la récurrence). `nil` pour
    /// les cartes « Repas à revoir » classiques.
    let contexteAffiche: String?

    /// Ratio effectif du **dernier** repas (grammes de glucides couverts par
    /// 1 unité), déjà persisté sur le repas. Affiché en pied de carte à la
    /// place des glucides bruts : c'est lui qui explique le verdict, la
    /// quantité seule ne dit rien sans la dose en face.
    let ratioApplique: Double?

    /// Faits du hub survenus pendant la fenêtre post-repas du **dernier**
    /// repas (bolus, corrections, lente, autres repas, sport), superposés à
    /// la courbe colorée. Vide si rien à signaler.
    let evenements: [EvenementCourbe]

    /// Horodatage du **dernier** repas du groupe — affiché à droite du titre
    /// pour distinguer deux cartes qui partagent le même moment (« Petit
    /// déjeuner » × plusieurs jours) une fois le titre passé du nom de
    /// l'aliment au moment de la journée.
    let heureDerniereOccurrence: Date

    /// Id du **`Repas` réel** (SwiftData) qui a motivé cette carte — le
    /// dernier occurrence pour un groupe récurrent, l'unique repas pour un
    /// contexte libre. Distinct de `id` (généré à chaque reconstruction de la
    /// carte, donc instable d'un recalcul à l'autre) : c'est `idRepasSource`
    /// qui sert de clé stable pour masquer une carte (`RepasARevoirMasquesService`)
    /// — masquer par ce seul id fait automatiquement réapparaître la carte
    /// si ce même repas se reproduit plus tard avec un nouveau mauvais
    /// résultat (nouveau `Repas`, donc nouvel id, absent du set masqué).
    let idRepasSource: UUID

    init(
        aliments: [Aliment],
        nombreOccurrences: Int,
        occurrencesPassees: [OccurrencePassee],
        pointsDerniereFois: [PointCourbeRepas],
        evenementMinutes: Int,
        evenementValeur: Double,
        estHypo: Bool,
        glucidesMin: Int,
        glucidesMax: Int,
        libelleSection: String = "",
        badgesAjustements: [BadgeAjustement] = [],
        contexteAffiche: String? = nil,
        ratioApplique: Double? = nil,
        evenements: [EvenementCourbe] = [],
        heureDerniereOccurrence: Date = Date(),
        idRepasSource: UUID = UUID()
    ) {
        self.aliments = aliments
        self.nombreOccurrences = nombreOccurrences
        self.occurrencesPassees = occurrencesPassees
        self.pointsDerniereFois = pointsDerniereFois
        self.evenementMinutes = evenementMinutes
        self.evenementValeur = evenementValeur
        self.estHypo = estHypo
        self.glucidesMin = glucidesMin
        self.glucidesMax = glucidesMax
        self.libelleSection = libelleSection
        self.badgesAjustements = badgesAjustements
        self.contexteAffiche = contexteAffiche
        self.ratioApplique = ratioApplique
        self.evenements = evenements
        self.heureDerniereOccurrence = heureDerniereOccurrence
        self.idRepasSource = idRepasSource
    }

    // MARK: Computed

    /// Aliment le plus contributeur en glucides — celui qui pilote la
    /// réponse glycémique et qui sert d'emoji / nom de titre.
    var alimentPrincipal: Aliment? {
        aliments.max(by: { $0.glucides < $1.glucides })
    }

    /// `true` si **n'importe quelle** courbe (passée ou dernière fois)
    /// descend sous le seuil d'hypo 70 mg/dL. Pilote l'affichage
    /// conditionnel du `RuleMark` rouge à 70 dans le chart : pas la
    /// peine de tracer la ligne si aucune courbe ne s'en approche.
    var aHypoDansCourbes: Bool {
        let toutesValeurs = pointsDerniereFois.map(\.glycemie)
            + occurrencesPassees.flatMap { $0.points.map(\.glycemie) }
        return toutesValeurs.contains { $0 < 70 }
    }

    /// Nombre d'occurrences hors cible, **dernière fois comprise** — celle-ci
    /// l'est toujours par construction (c'est ce qui motive la carte).
    var nombreOccurrencesHorsCible: Int {
        1 + occurrencesPassees.filter(\.horsCible).count
    }

    /// « 1 fois sur 3 hors cible » — le fait que la carte ne disait pas.
    ///
    /// Sans ce dénominateur, une carte affichant « ×3 » laisse croire que le
    /// plat pose problème à chaque fois, alors qu'il peut n'avoir raté qu'une
    /// seule fois sur trois : deux lectures opposées pour un même visuel.
    /// `nil` sur une occurrence unique (« 1 fois sur 1 » n'apprend rien).
    var libelleRecurrenceEchecs: String? {
        guard nombreOccurrences > 1 else { return nil }
        return "\(nombreOccurrencesHorsCible) fois sur \(nombreOccurrences) hors cible"
    }

    /// `true` quand **toutes** les occurrences connues sont hors cible — le
    /// plat échoue systématiquement, pas ponctuellement. Pilote une teinte
    /// d'alerte sur le compteur : c'est le cas qui justifie de revoir le
    /// ratio, par opposition à un raté isolé.
    var echecSystematique: Bool {
        nombreOccurrences > 1 && nombreOccurrencesHorsCible == nombreOccurrences
    }

    /// Couleur de sévérité appliquée à la courbe « dernière fois », au
    /// PointMark du pic et à l'info pic textuelle.
    ///
    /// Règles (cohérentes avec les seuils cible/hyper/hyper sévère) :
    /// - Hypo (< 70) → rouge
    /// - En cible (pic < 180) → vert
    /// - Hyper (180–250) → orange
    /// - Hyper sévère (> 250) → rouge
    var couleurSeverite: Color {
        if estHypo { return .red }
        if evenementValeur < 180 { return .green }
        if evenementValeur <= 250 { return .orange }
        return .red
    }

    /// Libellé compact de l'info pic — « Pic 235 · après 1h15 » ou
    /// « Hypo 62 · après 2h00 » selon la nature de l'événement.
    var libelleEvenement: String {
        let label = estHypo ? "Hypo" : "Pic"
        return "\(label) \(Int(evenementValeur.rounded())) · après \(formatHeureMinutes(evenementMinutes))"
    }

    /// Triangle directionnel pour l'info pic : ▲ pour un hyper,
    /// ▼ pour une hypo.
    var symboleEvenement: String {
        estHypo ? "▼" : "▲"
    }

    /// Ratio formaté « 1u/12g ». `nil` quand le repas n'a pas de ratio
    /// effectif persisté (repli gracieux : le pied de carte l'omet).
    var ratioFormate: String? {
        guard let ratioApplique, ratioApplique > 0 else { return nil }
        return "1u/\(Int(ratioApplique.rounded()))g"
    }

    /// Date/heure relative de la dernière occurrence — « Hier · 8h15 »,
    /// « Aujourd'hui · 12h30 », ou « Lun. 12 juin · 8h15 » au-delà. Distingue
    /// deux cartes qui partagent le même titre (le moment de la journée)
    /// depuis que celui-ci a remplacé le nom de l'aliment.
    var libelleDate: String {
        let cal = Calendar.current
        let jour: String
        if cal.isDateInToday(heureDerniereOccurrence) {
            jour = "Aujourd'hui"
        } else if cal.isDateInYesterday(heureDerniereOccurrence) {
            jour = "Hier"
        } else {
            jour = Self.formatterJourCourt.string(from: heureDerniereOccurrence).capitalizedFirstLetter
        }
        return "\(jour) · \(Self.formatterHeure.string(from: heureDerniereOccurrence))"
    }

    private static let formatterJourCourt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private static let formatterHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "H'h'mm"
        return f
    }()

    /// Domaine Y du graphe, **adapté aux données** au lieu d'un `50…300` figé :
    /// sur un repas qui plafonne à 130, un domaine fixe écrasait toute la
    /// courbe dans le bas du cadre et ne montrait plus rien. Marge de 15 mg/dL
    /// de part et d'autre, bornes élargies pour toujours contenir les seuils
    /// pertinents (70 si une hypo existe, 180 comme repère de cible).
    var domaineY: ClosedRange<Double> {
        let valeurs = pointsDerniereFois.map(\.glycemie)
            + occurrencesPassees.flatMap { $0.points.map(\.glycemie) }
        guard let brut = valeurs.min(), let haut = valeurs.max() else { return 50...300 }
        var bas = brut
        var plafond = haut
        // Le repère 180 (cible haute) reste visible dès qu'on s'en approche ;
        // le repère 70 uniquement si une courbe descend effectivement en hypo.
        if plafond >= 160 { plafond = max(plafond, 185) }
        if aHypoDansCourbes { bas = min(bas, 65) }
        return (bas - 15)...(plafond + 15)
    }

    /// Format « 1h15 » ou « 45 min » pour la durée depuis le repas.
    private func formatHeureMinutes(_ minutes: Int) -> String {
        let heures = minutes / 60
        let reste = minutes % 60
        if heures == 0 { return "\(reste) min" }
        return "\(heures)h\(String(format: "%02d", reste))"
    }
}
