//
//  ProfilUtilisateur.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation

/// Profil utilisateur — agrège l'ensemble des paramètres médicaux et
/// préférences éditables depuis la page Profil (sheet).
///
/// Toutes les valeurs proviennent de saisies utilisateur (typiquement
/// dictées par son médecin) ; l'app ne les modifie jamais
/// automatiquement et ne calcule jamais de dose à partir de ces
/// valeurs — elle peut uniquement les analyser pour faire émerger
/// des observations.
///
/// La forme `Codable` permet la persistance brute en JSON via
/// `UserDefaults` (cf. `ProfilService`) ; pas de versioning explicite
/// pour l'instant — le profil est suffisamment plat pour qu'un ajout
/// de champ optionnel reste rétrocompatible.
struct ProfilUtilisateur: Codable, Equatable, Sendable {

    // MARK: - Informations de base

    var prenom: String

    /// Photo de profil — JPEG réduite (plus grand côté ~512 px), encodée
    /// en base64 dans le JSON `UserDefaults`. `nil` → l'avatar retombe
    /// sur l'initiale du prénom. Champ optionnel avec valeur par défaut :
    /// rétrocompatible avec les profils déjà persistés (clé absente
    /// décodée en `nil`) et sans toucher aux initialiseurs existants.
    var photoData: Data? = nil

    var poidsKg: Double?

    // MARK: - Insuline

    var insulineRapide: InsulineRapide
    var insulineLente: InsulineLente

    /// Durée d'action (DIA) de l'insuline rapide, en heures. Sert au
    /// calcul de l'IOB (Insulin On Board) — pas d'usage clinique direct.
    /// Range UI : 3–6h, pas 0,5h.
    var dureeActionInsulineHeures: Double

    /// Intervalle minimum que l'utilisateur s'autorise entre deux doses de
    /// lente, en heures. Pilote l'heure « habituelle » adaptative du rappel
    /// (accueil + carte médications) : `dernière prise + cet intervalle`,
    /// plutôt qu'une heure fixe chaque jour. Optionnel avec fallback
    /// `intervalleMinimumLenteEffectif` — même pattern que `photoData` —
    /// pour rester rétrocompatible avec les profils déjà persistés.
    var intervalleMinimumLenteHeures: Double? = nil

    /// Valeur effective de l'intervalle minimum lente — 22h30 par défaut
    /// tant que l'utilisateur n'a rien réglé.
    var intervalleMinimumLenteEffectif: Double {
        intervalleMinimumLenteHeures ?? 22.5
    }

    // MARK: - Ratios glucides / insuline

    var modeRatio: ModeRatio

    /// Utilisé uniquement si `modeRatio == .unique`. Optionnel pour
    /// permettre l'état « non encore défini » au premier démarrage.
    var ratioUnique: Double?

    /// Utilisé uniquement si `modeRatio == .parMoment`. Chaque champ
    /// reste optionnel jusqu'à saisie explicite.
    var ratiosParMoment: RatiosParMoment

    /// ISF (Insulin Sensitivity Factor) — combien 1u baisse la
    /// glycémie en mg/dL. Optionnel : un nombre de patients ne le
    /// connaissent pas et l'app reste utile sans.
    var ratioCorrection: Double?

    /// Ratios spécifiques appliqués après une activité sportive, par type
    /// de sport. Optionnel avec fallback `ratiosSportEffectifs` — même
    /// pattern que `photoData` — pour rester rétrocompatible avec les
    /// profils déjà persistés (clé absente décodée en `nil`).
    var ratiosSport: RatiosSport? = nil

    /// Valeur effective des ratios sport — instance vide (aucun ratio
    /// configuré, fenêtre par défaut) tant que l'utilisateur n'a rien réglé.
    var ratiosSportEffectifs: RatiosSport {
        ratiosSport ?? RatiosSport()
    }

    // MARK: - Reste

    var horairesRepas: HorairesRepas
    var seuilsGlycemiques: SeuilsGlycemiques
    var preferencesAvancees: PreferencesAvancees

    // MARK: - Validation

    /// `true` si tous les champs requis sont renseignés. La sheet
    /// laisse l'utilisateur fermer même si invalide ; cette propriété
    /// servira au démarrage de l'app pour rediriger vers le profil
    /// (à câbler plus tard).
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
