//
//  ProfilService.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation
import Observation

/// Service en mémoire qui gère le `ProfilUtilisateur` courant et sa
/// persistance.
///
/// Persistance via `UserDefaults` en JSON — c'est suffisamment léger
/// (un objet plat de quelques dizaines d'octets) pour ne pas justifier
/// SwiftData ou un fichier dédié à ce stade. Une bascule plus tard
/// vers un backend NestJS / Prisma se fera derrière la même API
/// publique (`profil`, `mettreAJour(_:)`).
///
/// Pattern auto-save : chaque modification passe par `mettreAJour(_:)`
/// qui mute le profil et appelle immédiatement `sauvegarder()`. Pas
/// de bouton « Enregistrer » global dans la sheet — c'est cohérent
/// avec l'app Réglages d'iOS.
///
/// `@MainActor` : le service est lu et écrit depuis l'UI (vues
/// `@Observable`) ; le contraindre au main actor évite tout besoin de
/// synchronisation et reste compatible avec la concurrence stricte
/// Swift 6.
@Observable
@MainActor
final class ProfilService {

    /// Instance partagée — utilisée par l'app en exécution réelle.
    /// Les previews construisent leurs propres instances via les mocks
    /// statiques (`mockComplet()`, `mockVide()`, etc.) pour rester
    /// isolées et déterministes.
    static let shared = ProfilService()

    // MARK: - État observable

    /// Profil courant. `private(set)` pour forcer toutes les écritures
    /// à passer par `mettreAJour(_:)` (et donc déclencher la
    /// sauvegarde).
    private(set) var profil: ProfilUtilisateur

    // MARK: - Persistance

    private let cleStockage = "profilUtilisateur"

    /// Stockage injectable — par défaut `.standard`, mais les mocks
    /// utilisent un `UserDefaults` isolé pour ne pas polluer le vrai
    /// profil de l'utilisateur lors d'un build de previews.
    private let stockage: UserDefaults

    // MARK: - Init

    /// Constructeur privé pour le singleton de production.
    private init() {
        self.stockage = .standard
        self.profil = Self.charger(depuis: .standard, cle: "profilUtilisateur")
            ?? ProfilUtilisateur.parDefaut()
    }

    /// Constructeur interne pour les mocks — permet d'injecter un
    /// `UserDefaults` isolé (suite séparée) et un profil de départ.
    private init(profil: ProfilUtilisateur, stockage: UserDefaults) {
        self.stockage = stockage
        self.profil = profil
    }

    // MARK: - Mutation

    /// Mute le profil via une closure inout et persiste immédiatement.
    ///
    /// Le pattern closure permet aux vues de modifier plusieurs champs
    /// en une seule opération (« j'écris ratio + mode en bascule ») et
    /// garantit qu'une seule sauvegarde sera émise au lieu d'une par
    /// champ.
    func mettreAJour(_ modifications: (inout ProfilUtilisateur) -> Void) {
        modifications(&profil)
        sauvegarder()
    }

    // MARK: - Persistance privée

    private static func charger(
        depuis stockage: UserDefaults,
        cle: String
    ) -> ProfilUtilisateur? {
        guard let data = stockage.data(forKey: cle) else { return nil }
        do {
            return try JSONDecoder().decode(ProfilUtilisateur.self, from: data)
        } catch {
            // Profil corrompu (changement de schéma cassant, données
            // bidouillées) : on log et on retourne nil pour retomber
            // sur la valeur par défaut, plutôt que de planter le démarrage.
            print("⚠️ ProfilService: décodage échoué (\(error)) — fallback défaut.")
            return nil
        }
    }

    private func sauvegarder() {
        do {
            let data = try JSONEncoder().encode(profil)
            stockage.set(data, forKey: cleStockage)
        } catch {
            // Encodage qui échoue est extrêmement improbable pour des
            // types `Codable` triviaux — on log seulement, sans casser
            // l'UI. Le prochain `mettreAJour` retentera.
            print("⚠️ ProfilService: encodage échoué (\(error)).")
        }
    }
}

// MARK: - Mocks pour previews

extension ProfilService {

    /// `UserDefaults` isolé pour les mocks de previews — évite toute
    /// interférence avec le profil réel de l'utilisateur. La suite
    /// est volontairement nommée pour qu'on puisse la nettoyer
    /// manuellement si besoin.
    private static func stockageMock() -> UserDefaults {
        UserDefaults(suiteName: "ProfilService.preview")
            ?? .standard
    }

    /// Profil entièrement renseigné, mode ratio unique — utilisé pour
    /// le scénario par défaut « utilisateur déjà configuré ».
    static func mockComplet() -> ProfilService {
        let profil = ProfilUtilisateur(
            prenom: "Camille",
            poidsKg: 78,
            insulineRapide: .novorapid,
            insulineLente: .toujeo,
            dureeActionInsulineHeures: 4,
            modeRatio: .unique,
            ratioUnique: 12,
            ratiosParMoment: RatiosParMoment(),
            ratioCorrection: 40,
            horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(),
            preferencesAvancees: PreferencesAvancees()
        )
        return ProfilService(profil: profil, stockage: stockageMock())
    }

    /// Profil entièrement renseigné, mode ratio par moment — pour
    /// vérifier l'affichage des 4 lignes de ratios.
    static func mockAvecRatiosParMoment() -> ProfilService {
        let profil = ProfilUtilisateur(
            prenom: "Camille",
            poidsKg: 78,
            insulineRapide: .fiasp,
            insulineLente: .tresiba,
            dureeActionInsulineHeures: 3.5,
            modeRatio: .parMoment,
            ratioUnique: nil,
            ratiosParMoment: RatiosParMoment(
                petitDejeuner: 8,
                dejeuner: 12,
                gouter: 15,
                diner: 10
            ),
            ratioCorrection: 35,
            horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(hypoglycemie: 75, hyperglycemie: 170),
            preferencesAvancees: PreferencesAvancees(margeAlerteDose: 1.5)
        )
        return ProfilService(profil: profil, stockage: stockageMock())
    }

    /// Profil au tout premier démarrage — tous les champs requis sont
    /// vides pour permettre de visualiser les erreurs « Requis » dans
    /// la sheet.
    static func mockVide() -> ProfilService {
        ProfilService(
            profil: ProfilUtilisateur.parDefaut(),
            stockage: stockageMock()
        )
    }
}
