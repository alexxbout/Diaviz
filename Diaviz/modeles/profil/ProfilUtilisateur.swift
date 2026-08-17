//
//  ProfilUtilisateur.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation
import SwiftData

/// Profil utilisateur — agrège l'ensemble des paramètres médicaux et
/// préférences éditables depuis la page Profil (sheet).
///
/// Toutes les valeurs proviennent de saisies utilisateur (typiquement
/// dictées par son médecin) ; l'app ne les modifie jamais
/// automatiquement et ne calcule jamais de dose à partir de ces
/// valeurs — elle peut uniquement les analyser pour faire émerger
/// des observations.
///
/// Entité du hub (`@Model`), une seule ligne en pratique — voir
/// `ProfilService.demarrer(contexte:)` pour la logique fetch-ou-création
/// et le départage si plusieurs lignes coexistent temporairement (insert
/// concurrent sur deux appareils avant sync). Valeurs par défaut ci-dessous :
/// filet de secours schema-only exigé par CloudKit, jamais exercé par le
/// flux normal (l'`init` garde ses paramètres obligatoires) — voir
/// `GlucoseReading` pour le principe.
@Model
final class ProfilUtilisateur {

    var id: UUID = UUID()

    /// Horodatage de la dernière mutation (`ProfilService.mettreAJour`) —
    /// sert de départage si plusieurs lignes existent temporairement, et
    /// est utile en soi pour du diagnostic.
    var derniereMiseAJour: Date = Date()

    // MARK: - Informations de base

    var prenom: String = ""

    /// Photo de profil — JPEG réduite (plus grand côté ~512 px). `nil` →
    /// l'avatar retombe sur l'initiale du prénom.
    var photoData: Data? = nil

    var poidsKg: Double? = nil

    // MARK: - Insuline

    var insulineRapide: InsulineRapide = InsulineRapide.novorapid
    var insulineLente: InsulineLente = InsulineLente.lantus

    /// Durée d'action (DIA) de l'insuline rapide, en heures. Sert au
    /// calcul de l'IOB (Insulin On Board) — pas d'usage clinique direct.
    /// Range UI : 3–6h, pas 0,5h.
    var dureeActionInsulineHeures: Double = 4

    /// Intervalle minimum que l'utilisateur s'autorise entre deux doses de
    /// lente, en heures. Pilote l'heure « habituelle » adaptative du rappel
    /// (accueil + carte médications) : `dernière prise + cet intervalle`,
    /// plutôt qu'une heure fixe chaque jour. Optionnel avec fallback
    /// `intervalleMinimumLenteEffectif`.
    var intervalleMinimumLenteHeures: Double? = nil

    /// Valeur effective de l'intervalle minimum lente — 22h30 par défaut
    /// tant que l'utilisateur n'a rien réglé.
    var intervalleMinimumLenteEffectif: Double {
        intervalleMinimumLenteHeures ?? 22.5
    }

    // MARK: - Ratios glucides / insuline

    var modeRatio: ModeRatio = ModeRatio.unique

    /// Utilisé uniquement si `modeRatio == .unique`. Optionnel pour
    /// permettre l'état « non encore défini » au premier démarrage.
    var ratioUnique: Double? = nil

    /// Stockage privé optionnel — CloudKit plante au cast (« Could not
    /// cast value of type 'Optional<Any>' ») sur les propriétés struct
    /// custom non-optionnelles, même avec une valeur par défaut : contrairement
    /// aux types natifs Core Data (Date, UUID, enum brut), une struct
    /// `Codable` imbriquée a besoin d'une vraie optionalité. Même pattern
    /// que `_aliments`/`aliments` sur `Repas`/`Resucrage`.
    private var _ratiosParMoment: RatiosParMoment? = nil

    /// Utilisé uniquement si `modeRatio == .parMoment`. Chaque champ
    /// reste optionnel jusqu'à saisie explicite.
    var ratiosParMoment: RatiosParMoment {
        get { _ratiosParMoment ?? RatiosParMoment() }
        set { _ratiosParMoment = newValue }
    }

    /// Date du dernier changement de valeur pour chaque ratio, par moment —
    /// borne le mining R1 aux repas postérieurs. Optionnel avec fallback
    /// `datesChangementRatioEffectives`.
    var datesChangementRatio: DatesChangementRatio? = nil

    /// Valeur effective des dates de changement — instance vide (aucun
    /// changement tracé, tout l'historique reste éligible) tant qu'aucun
    /// ratio n'a été modifié depuis la configuration initiale.
    var datesChangementRatioEffectives: DatesChangementRatio {
        datesChangementRatio ?? DatesChangementRatio()
    }

    /// ISF (Insulin Sensitivity Factor) — combien 1u baisse la
    /// glycémie en mg/dL. Optionnel : un nombre de patients ne le
    /// connaissent pas et l'app reste utile sans.
    var ratioCorrection: Double? = nil

    /// Ratios spécifiques appliqués après une activité sportive, par type
    /// de sport. Optionnel avec fallback `ratiosSportEffectifs`.
    var ratiosSport: RatiosSport? = nil

    /// Valeur effective des ratios sport — instance vide (aucun ratio
    /// configuré, fenêtre par défaut) tant que l'utilisateur n'a rien réglé.
    var ratiosSportEffectifs: RatiosSport {
        ratiosSport ?? RatiosSport()
    }

    // MARK: - Reste

    /// Stockage privé optionnel — même raison que `_ratiosParMoment` : les
    /// structs `Codable` imbriquées doivent être vraiment optionnelles pour
    /// CloudKit, une valeur par défaut Swift seule ne suffit pas.
    private var _horairesRepas: HorairesRepas? = nil
    var horairesRepas: HorairesRepas {
        get { _horairesRepas ?? HorairesRepas.defaut() }
        set { _horairesRepas = newValue }
    }

    private var _seuilsGlycemiques: SeuilsGlycemiques? = nil
    var seuilsGlycemiques: SeuilsGlycemiques {
        get { _seuilsGlycemiques ?? SeuilsGlycemiques() }
        set { _seuilsGlycemiques = newValue }
    }

    private var _preferencesAvancees: PreferencesAvancees? = nil
    var preferencesAvancees: PreferencesAvancees {
        get { _preferencesAvancees ?? PreferencesAvancees() }
        set { _preferencesAvancees = newValue }
    }

    init(
        id: UUID = UUID(),
        derniereMiseAJour: Date = Date(),
        prenom: String,
        photoData: Data? = nil,
        poidsKg: Double?,
        insulineRapide: InsulineRapide,
        insulineLente: InsulineLente,
        dureeActionInsulineHeures: Double,
        intervalleMinimumLenteHeures: Double? = nil,
        modeRatio: ModeRatio,
        ratioUnique: Double?,
        ratiosParMoment: RatiosParMoment,
        datesChangementRatio: DatesChangementRatio? = nil,
        ratioCorrection: Double?,
        ratiosSport: RatiosSport? = nil,
        horairesRepas: HorairesRepas,
        seuilsGlycemiques: SeuilsGlycemiques,
        preferencesAvancees: PreferencesAvancees
    ) {
        self.id = id
        self.derniereMiseAJour = derniereMiseAJour
        self.prenom = prenom
        self.photoData = photoData
        self.poidsKg = poidsKg
        self.insulineRapide = insulineRapide
        self.insulineLente = insulineLente
        self.dureeActionInsulineHeures = dureeActionInsulineHeures
        self.intervalleMinimumLenteHeures = intervalleMinimumLenteHeures
        self.modeRatio = modeRatio
        self.ratioUnique = ratioUnique
        self.ratiosParMoment = ratiosParMoment
        self.datesChangementRatio = datesChangementRatio
        self.ratioCorrection = ratioCorrection
        self.ratiosSport = ratiosSport
        self.horairesRepas = horairesRepas
        self.seuilsGlycemiques = seuilsGlycemiques
        self.preferencesAvancees = preferencesAvancees
    }

    // MARK: - Validation

    /// `true` si tous les champs requis sont renseignés. La sheet
    /// laisse l'utilisateur fermer même si invalide ; cette propriété
    /// sert aussi au démarrage de l'app pour décider onboarding vs app
    /// normale (voir `AppTabVues`).
    var estValide: Bool {
        guard !prenom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch modeRatio {
        case .unique:
            return ratioUnique != nil
        case .parMoment:
            return ratiosParMoment.estComplete
        }
    }

    // MARK: - Copie de champs

    /// Copie tous les champs de `autre` sur `self`, en préservant `id`.
    /// Utilisé par `ProfilService.reinitialiser()` et par les previews qui
    /// posent un profil complet d'un bloc : remplacer l'instance
    /// (`$0 = ProfilUtilisateur(...)`) la détacherait du contexte SwiftData,
    /// et les modifications ne seraient plus persistées.
    func appliquer(depuis autre: ProfilUtilisateur) {
        prenom = autre.prenom
        photoData = autre.photoData
        poidsKg = autre.poidsKg
        insulineRapide = autre.insulineRapide
        insulineLente = autre.insulineLente
        dureeActionInsulineHeures = autre.dureeActionInsulineHeures
        intervalleMinimumLenteHeures = autre.intervalleMinimumLenteHeures
        modeRatio = autre.modeRatio
        ratioUnique = autre.ratioUnique
        ratiosParMoment = autre.ratiosParMoment
        datesChangementRatio = autre.datesChangementRatio
        ratioCorrection = autre.ratioCorrection
        ratiosSport = autre.ratiosSport
        horairesRepas = autre.horairesRepas
        seuilsGlycemiques = autre.seuilsGlycemiques
        preferencesAvancees = autre.preferencesAvancees
        derniereMiseAJour = Date()
    }

    // MARK: - Valeur par défaut

    /// Profil neuf — utilisé au tout premier démarrage avant que
    /// l'utilisateur n'ouvre la page Profil. Tous les champs « libres »
    /// (prénom, poids, ratios) sont vides ; les champs avec contraintes
    /// dures (DIA, horaires, seuils) reçoivent des valeurs raisonnables
    /// pour que l'UI ait toujours quelque chose à afficher.
    static func parDefaut() -> ProfilUtilisateur {
        ProfilUtilisateur(
            prenom: "",
            poidsKg: nil,
            insulineRapide: .novorapid,
            insulineLente: .lantus,
            dureeActionInsulineHeures: 4,
            modeRatio: .unique,
            ratioUnique: nil,
            ratiosParMoment: RatiosParMoment(),
            ratioCorrection: nil,
            horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(),
            preferencesAvancees: PreferencesAvancees()
        )
    }
}
