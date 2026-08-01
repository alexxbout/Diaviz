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
    /// incluse — `pointsOccurrencesPassees.count + 1` doit être égal
    /// à cette valeur.
    let nombreOccurrences: Int

    /// Toutes les courbes des occurrences passées **sauf** la dernière.
    /// Chacune est rendue en gris discret dans le mini-chart pour
    /// donner une impression de nuage / dispersion. Si le tableau est
    /// vide (un seul enregistrement total), seule la courbe colorée
    /// « dernière fois » apparaît.
    let pointsOccurrencesPassees: [[PointCourbeRepas]]

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
        pointsOccurrencesPassees: [[PointCourbeRepas]],
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
        self.pointsOccurrencesPassees = pointsOccurrencesPassees
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
            + pointsOccurrencesPassees.flatMap { $0.map(\.glycemie) }
        return toutesValeurs.contains { $0 < 70 }
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
            + pointsOccurrencesPassees.flatMap { $0.map(\.glycemie) }
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

// MARK: - Mocks

extension RepasARevoir {

    /// Big Mac — hyper modéré (235 mg/dL), 5 occurrences (4 courbes
    /// passées en nuage gris + 1 colorée orange). Glucides 55–70g.
    static let mockBigMac = RepasARevoir(
        aliments: [
            Aliment(emoji: "🍔", nom: "Big Mac", quantite: 220, glucides: 45, insuline: 4.5),
            Aliment(emoji: "🍟", nom: "Frites moyennes", quantite: 110, glucides: 42, insuline: 3.5),
            Aliment(emoji: "🥤", nom: "Coca", quantite: 250, glucides: 27, insuline: 2.5),
        ],
        nombreOccurrences: 5,
        pointsOccurrencesPassees: [
            // 4 occurrences passées, peaks 185–220, échelonnés sur
            // 60–85 min — dispersion modérée, repas "presque
            // prévisible" sauf la dernière fois.
            [
                PointCourbeRepas(minutes: 0,   glycemie: 105),
                PointCourbeRepas(minutes: 15,  glycemie: 118),
                PointCourbeRepas(minutes: 30,  glycemie: 142),
                PointCourbeRepas(minutes: 45,  glycemie: 168),
                PointCourbeRepas(minutes: 60,  glycemie: 185),
                PointCourbeRepas(minutes: 75,  glycemie: 195),
                PointCourbeRepas(minutes: 90,  glycemie: 188),
                PointCourbeRepas(minutes: 105, glycemie: 170),
                PointCourbeRepas(minutes: 120, glycemie: 150),
                PointCourbeRepas(minutes: 135, glycemie: 132),
                PointCourbeRepas(minutes: 150, glycemie: 120),
                PointCourbeRepas(minutes: 165, glycemie: 112),
                PointCourbeRepas(minutes: 180, glycemie: 108),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 112),
                PointCourbeRepas(minutes: 15,  glycemie: 125),
                PointCourbeRepas(minutes: 30,  glycemie: 152),
                PointCourbeRepas(minutes: 45,  glycemie: 178),
                PointCourbeRepas(minutes: 60,  glycemie: 200),
                PointCourbeRepas(minutes: 75,  glycemie: 210),
                PointCourbeRepas(minutes: 90,  glycemie: 205),
                PointCourbeRepas(minutes: 105, glycemie: 188),
                PointCourbeRepas(minutes: 120, glycemie: 165),
                PointCourbeRepas(minutes: 135, glycemie: 145),
                PointCourbeRepas(minutes: 150, glycemie: 128),
                PointCourbeRepas(minutes: 165, glycemie: 118),
                PointCourbeRepas(minutes: 180, glycemie: 112),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 100),
                PointCourbeRepas(minutes: 15,  glycemie: 112),
                PointCourbeRepas(minutes: 30,  glycemie: 132),
                PointCourbeRepas(minutes: 45,  glycemie: 158),
                PointCourbeRepas(minutes: 60,  glycemie: 178),
                PointCourbeRepas(minutes: 75,  glycemie: 182),
                PointCourbeRepas(minutes: 90,  glycemie: 172),
                PointCourbeRepas(minutes: 105, glycemie: 155),
                PointCourbeRepas(minutes: 120, glycemie: 138),
                PointCourbeRepas(minutes: 135, glycemie: 125),
                PointCourbeRepas(minutes: 150, glycemie: 115),
                PointCourbeRepas(minutes: 165, glycemie: 108),
                PointCourbeRepas(minutes: 180, glycemie: 105),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 115),
                PointCourbeRepas(minutes: 15,  glycemie: 128),
                PointCourbeRepas(minutes: 30,  glycemie: 158),
                PointCourbeRepas(minutes: 45,  glycemie: 188),
                PointCourbeRepas(minutes: 60,  glycemie: 210),
                PointCourbeRepas(minutes: 75,  glycemie: 218),
                PointCourbeRepas(minutes: 90,  glycemie: 215),
                PointCourbeRepas(minutes: 105, glycemie: 198),
                PointCourbeRepas(minutes: 120, glycemie: 172),
                PointCourbeRepas(minutes: 135, glycemie: 148),
                PointCourbeRepas(minutes: 150, glycemie: 130),
                PointCourbeRepas(minutes: 165, glycemie: 118),
                PointCourbeRepas(minutes: 180, glycemie: 110),
            ],
        ],
        pointsDerniereFois: [
            PointCourbeRepas(minutes: 0,   glycemie: 110),
            PointCourbeRepas(minutes: 15,  glycemie: 130),
            PointCourbeRepas(minutes: 30,  glycemie: 165),
            PointCourbeRepas(minutes: 45,  glycemie: 195),
            PointCourbeRepas(minutes: 60,  glycemie: 220),
            PointCourbeRepas(minutes: 75,  glycemie: 235),
            PointCourbeRepas(minutes: 90,  glycemie: 225),
            PointCourbeRepas(minutes: 105, glycemie: 200),
            PointCourbeRepas(minutes: 120, glycemie: 175),
            PointCourbeRepas(minutes: 135, glycemie: 150),
            PointCourbeRepas(minutes: 150, glycemie: 130),
            PointCourbeRepas(minutes: 165, glycemie: 115),
            PointCourbeRepas(minutes: 180, glycemie: 108),
        ],
        evenementMinutes: 75,
        evenementValeur: 235,
        estHypo: false,
        glucidesMin: 55,
        glucidesMax: 70,
        libelleSection: "Déjeuner",
        ratioApplique: 11,
        evenements: [
            EvenementCourbe(genre: .bolusRepas, minutes: 0, libelle: "10,5 u"),
            EvenementCourbe(genre: .correction, minutes: 105, libelle: "2 u"),
        ]
    )

    /// Pizza Margherita + Tiramisu — hyper sévère (265 mg/dL),
    /// 3 occurrences (2 courbes passées + 1 dernière fois). Glucides
    /// 80–95g. Pic décalé tardivement (1h40) caractéristique des
    /// repas riches en graisses.
    static let mockPizza = RepasARevoir(
        aliments: [
            Aliment(emoji: "🍕", nom: "Pizza Margherita", quantite: 350, glucides: 65, insuline: 6.0),
            Aliment(emoji: "🍰", nom: "Tiramisu", quantite: 120, glucides: 28, insuline: 2.5),
        ],
        nombreOccurrences: 3,
        pointsOccurrencesPassees: [
            // 2 courbes passées, peaks 220–235 — moins haut que la
            // dernière fois mais toujours dans la zone hyper.
            [
                PointCourbeRepas(minutes: 0,   glycemie: 110),
                PointCourbeRepas(minutes: 15,  glycemie: 125),
                PointCourbeRepas(minutes: 30,  glycemie: 150),
                PointCourbeRepas(minutes: 45,  glycemie: 178),
                PointCourbeRepas(minutes: 60,  glycemie: 200),
                PointCourbeRepas(minutes: 75,  glycemie: 215),
                PointCourbeRepas(minutes: 90,  glycemie: 220),
                PointCourbeRepas(minutes: 105, glycemie: 212),
                PointCourbeRepas(minutes: 120, glycemie: 195),
                PointCourbeRepas(minutes: 135, glycemie: 175),
                PointCourbeRepas(minutes: 150, glycemie: 158),
                PointCourbeRepas(minutes: 165, glycemie: 142),
                PointCourbeRepas(minutes: 180, glycemie: 130),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 115),
                PointCourbeRepas(minutes: 15,  glycemie: 130),
                PointCourbeRepas(minutes: 30,  glycemie: 158),
                PointCourbeRepas(minutes: 45,  glycemie: 188),
                PointCourbeRepas(minutes: 60,  glycemie: 215),
                PointCourbeRepas(minutes: 75,  glycemie: 230),
                PointCourbeRepas(minutes: 90,  glycemie: 235),
                PointCourbeRepas(minutes: 105, glycemie: 225),
                PointCourbeRepas(minutes: 120, glycemie: 208),
                PointCourbeRepas(minutes: 135, glycemie: 188),
                PointCourbeRepas(minutes: 150, glycemie: 168),
                PointCourbeRepas(minutes: 165, glycemie: 150),
                PointCourbeRepas(minutes: 180, glycemie: 138),
            ],
        ],
        pointsDerniereFois: [
            PointCourbeRepas(minutes: 0,   glycemie: 115),
            PointCourbeRepas(minutes: 15,  glycemie: 135),
            PointCourbeRepas(minutes: 30,  glycemie: 165),
            PointCourbeRepas(minutes: 45,  glycemie: 195),
            PointCourbeRepas(minutes: 60,  glycemie: 225),
            PointCourbeRepas(minutes: 75,  glycemie: 248),
            PointCourbeRepas(minutes: 90,  glycemie: 260),
            // Point exact du pic, hors grille 15 min, pour caler le
            // PointMark dans la chart sans dépendre de l'interpolation.
            PointCourbeRepas(minutes: 100, glycemie: 265),
            PointCourbeRepas(minutes: 120, glycemie: 255),
            PointCourbeRepas(minutes: 135, glycemie: 235),
            PointCourbeRepas(minutes: 150, glycemie: 215),
            PointCourbeRepas(minutes: 165, glycemie: 198),
            PointCourbeRepas(minutes: 180, glycemie: 180),
        ],
        evenementMinutes: 100,
        evenementValeur: 265,
        estHypo: false,
        glucidesMin: 80,
        glucidesMax: 95,
        libelleSection: "Dîner",
        ratioApplique: 9,
        evenements: [
            EvenementCourbe(genre: .bolusRepas, minutes: 0, libelle: "8,5 u"),
            EvenementCourbe(genre: .lente, minutes: 150, libelle: "18 u"),
        ]
    )

    /// California roll — pic en cible (175 mg/dL), 2 occurrences
    /// (1 courbe passée + 1 dernière fois). Glucides 40–50g.
    /// Réponse rapide et plafonnée → couleur verte.
    static let mockSushi = RepasARevoir(
        aliments: [
            Aliment(emoji: "🍣", nom: "California roll", quantite: 200, glucides: 38, insuline: 3.5),
            Aliment(emoji: "🍲", nom: "Soupe miso", quantite: 200, glucides: 4, insuline: 0.0),
            Aliment(emoji: "🌱", nom: "Edamame", quantite: 100, glucides: 8, insuline: 0.5),
        ],
        nombreOccurrences: 2,
        pointsOccurrencesPassees: [
            // 1 seule courbe passée — peak doux 165 à 60 min,
            // très proche de la dernière fois (repas régulier).
            [
                PointCourbeRepas(minutes: 0,   glycemie: 100),
                PointCourbeRepas(minutes: 15,  glycemie: 112),
                PointCourbeRepas(minutes: 30,  glycemie: 135),
                PointCourbeRepas(minutes: 45,  glycemie: 155),
                PointCourbeRepas(minutes: 60,  glycemie: 165),
                PointCourbeRepas(minutes: 75,  glycemie: 158),
                PointCourbeRepas(minutes: 90,  glycemie: 145),
                PointCourbeRepas(minutes: 105, glycemie: 132),
                PointCourbeRepas(minutes: 120, glycemie: 120),
                PointCourbeRepas(minutes: 135, glycemie: 112),
                PointCourbeRepas(minutes: 150, glycemie: 105),
                PointCourbeRepas(minutes: 165, glycemie: 102),
                PointCourbeRepas(minutes: 180, glycemie: 100),
            ],
        ],
        pointsDerniereFois: [
            PointCourbeRepas(minutes: 0,   glycemie: 105),
            PointCourbeRepas(minutes: 15,  glycemie: 120),
            PointCourbeRepas(minutes: 30,  glycemie: 145),
            PointCourbeRepas(minutes: 45,  glycemie: 168),
            // Pic à 55 min, hors grille 15 min.
            PointCourbeRepas(minutes: 55,  glycemie: 175),
            PointCourbeRepas(minutes: 75,  glycemie: 165),
            PointCourbeRepas(minutes: 90,  glycemie: 150),
            PointCourbeRepas(minutes: 105, glycemie: 138),
            PointCourbeRepas(minutes: 120, glycemie: 125),
            PointCourbeRepas(minutes: 135, glycemie: 118),
            PointCourbeRepas(minutes: 150, glycemie: 112),
            PointCourbeRepas(minutes: 165, glycemie: 108),
            PointCourbeRepas(minutes: 180, glycemie: 105),
        ],
        evenementMinutes: 55,
        evenementValeur: 175,
        estHypo: false,
        glucidesMin: 40,
        glucidesMax: 50
    )

    /// Pad Thaï — hypo post-prandiale (62 mg/dL à T+2h), 3 occurrences.
    /// Glucides 60–75g. Pattern typique d'un surdosage d'insuline
    /// sur des glucides estimés trop haut : la courbe monte
    /// modérément à 140 puis plonge en hypo deux heures après —
    /// l'insuline continue d'agir alors que les glucides sont
    /// digérés. Couleur rouge (hypo).
    static let mockPadThai = RepasARevoir(
        aliments: [
            Aliment(emoji: "🍜", nom: "Pad Thaï", quantite: 380, glucides: 68, insuline: 6.5),
            Aliment(emoji: "🥜", nom: "Cacahuètes", quantite: 20, glucides: 4, insuline: 0.0),
        ],
        nombreOccurrences: 3,
        pointsOccurrencesPassees: [
            // 2 courbes passées qui oscillent doucement autour de
            // 120–150, sans franchir la cible — ce sont les "bonnes"
            // expériences précédentes qui rendent la dernière fois
            // d'autant plus surprenante.
            [
                PointCourbeRepas(minutes: 0,   glycemie: 115),
                PointCourbeRepas(minutes: 15,  glycemie: 125),
                PointCourbeRepas(minutes: 30,  glycemie: 138),
                PointCourbeRepas(minutes: 45,  glycemie: 145),
                PointCourbeRepas(minutes: 60,  glycemie: 142),
                PointCourbeRepas(minutes: 75,  glycemie: 138),
                PointCourbeRepas(minutes: 90,  glycemie: 132),
                PointCourbeRepas(minutes: 105, glycemie: 128),
                PointCourbeRepas(minutes: 120, glycemie: 125),
                PointCourbeRepas(minutes: 135, glycemie: 122),
                PointCourbeRepas(minutes: 150, glycemie: 120),
                PointCourbeRepas(minutes: 165, glycemie: 118),
                PointCourbeRepas(minutes: 180, glycemie: 115),
            ],
            [
                PointCourbeRepas(minutes: 0,   glycemie: 120),
                PointCourbeRepas(minutes: 15,  glycemie: 128),
                PointCourbeRepas(minutes: 30,  glycemie: 142),
                PointCourbeRepas(minutes: 45,  glycemie: 150),
                PointCourbeRepas(minutes: 60,  glycemie: 148),
                PointCourbeRepas(minutes: 75,  glycemie: 145),
                PointCourbeRepas(minutes: 90,  glycemie: 138),
                PointCourbeRepas(minutes: 105, glycemie: 132),
                PointCourbeRepas(minutes: 120, glycemie: 128),
                PointCourbeRepas(minutes: 135, glycemie: 125),
                PointCourbeRepas(minutes: 150, glycemie: 122),
                PointCourbeRepas(minutes: 165, glycemie: 120),
                PointCourbeRepas(minutes: 180, glycemie: 118),
            ],
        ],
        pointsDerniereFois: [
            // Montée modérée à 140 sur 60 min puis plongée en hypo :
            // T+2h = 62 mg/dL (point exact pour caler le PointMark),
            // récupération graduelle ensuite (resucrage implicite).
            PointCourbeRepas(minutes: 0,   glycemie: 118),
            PointCourbeRepas(minutes: 15,  glycemie: 125),
            PointCourbeRepas(minutes: 30,  glycemie: 132),
            PointCourbeRepas(minutes: 45,  glycemie: 138),
            PointCourbeRepas(minutes: 60,  glycemie: 140),
            PointCourbeRepas(minutes: 75,  glycemie: 130),
            PointCourbeRepas(minutes: 90,  glycemie: 112),
            PointCourbeRepas(minutes: 105, glycemie: 88),
            PointCourbeRepas(minutes: 120, glycemie: 62),
            PointCourbeRepas(minutes: 135, glycemie: 72),
            PointCourbeRepas(minutes: 150, glycemie: 88),
            PointCourbeRepas(minutes: 165, glycemie: 102),
            PointCourbeRepas(minutes: 180, glycemie: 112),
        ],
        evenementMinutes: 120,
        evenementValeur: 62,
        estHypo: true,
        glucidesMin: 60,
        glucidesMax: 75,
        libelleSection: "Dîner",
        ratioApplique: 10,
        evenements: [
            EvenementCourbe(genre: .bolusRepas, minutes: 0, libelle: "6,5 u"),
            EvenementCourbe(genre: .sport, minutes: 30, dureeMinutes: 45, libelle: "Marche 45 min"),
            EvenementCourbe(genre: .repas, minutes: 135, libelle: "15 g"),
        ]
    )
}
