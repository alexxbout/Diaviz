//
//  ProfilService.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import Foundation
import Observation
import SwiftData

/// Service en mémoire qui gère le `ProfilUtilisateur` courant et sa
/// persistance.
///
/// Persistance via SwiftData (le profil est une entité du hub comme les
/// autres, `ProfilUtilisateur.swift`) — ce qui le fait bénéficier de la
/// même synchronisation CloudKit que le reste des données, contrairement à
/// l'ancienne persistance `UserDefaults` locale-only (perdue à chaque
/// désinstallation).
///
/// Pattern de démarrage aligné sur `RepasService` : la vue crée le service
/// vide (`profil` retombe sur `ProfilUtilisateur.parDefaut()`, une instance
/// non suivie par SwiftData) puis lui passe le `ModelContext` de
/// l'environnement via `demarrer(contexte:)`, appelé depuis `.task` — pas
/// dans l'`init`, le `ModelContext` n'existe pas encore à ce moment-là.
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
    /// sauvegarde). Avant `demarrer(contexte:)`, retombe sur une instance
    /// neuve non suivie par SwiftData — dégradation gracieuse plutôt que
    /// crash si une vue lit le profil avant le câblage.
    private(set) var profil: ProfilUtilisateur = ProfilUtilisateur.parDefaut()

    // MARK: - Persistance

    /// Contexte du hub, fourni au démarrage. `nil` tant que `demarrer` n'a
    /// pas été appelé.
    private var modelContext: ModelContext?

    // MARK: - Init

    private init() {}

    // MARK: - Démarrage

    /// Branche le service sur le contexte du hub et adopte la ligne profil
    /// existante s'il y en a une. Idempotent.
    ///
    /// **N'insère volontairement rien** quand le store est vide : sur une
    /// réinstallation, l'import CloudKit du vrai profil peut arriver
    /// plusieurs dizaines de secondes après le lancement. Insérer une ligne
    /// vide tout de suite créerait un doublon qui (a) part lui-même vers
    /// iCloud et pollue le compte, et (b) porte une `derniereMiseAJour`
    /// d'aujourd'hui, donc gagnerait tout départage par date contre le vrai
    /// profil arrivé plus tard. La ligne n'est matérialisée qu'à la première
    /// vraie saisie de l'utilisateur (`mettreAJour`).
    func demarrer(contexte: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = contexte
        adopterMeilleureLigne()
    }

    /// Rattrape une ligne profil arrivée après coup depuis iCloud — appelé
    /// par `AppTabVues` à chaque import CloudKit réussi, et par l'écran de
    /// restauration pendant son attente active.
    ///
    /// Retourne `true` si le profil courant est désormais valide (donc
    /// réellement restauré), ce qui permet à l'appelant d'arrêter d'attendre.
    @discardableResult
    func rafraichirDepuisCloudKit() -> Bool {
        adopterMeilleureLigne()
        return profil.estValide
    }

    /// Choisit la ligne canonique parmi celles présentes et l'adopte, en
    /// nettoyant les lignes vides devenues inutiles.
    ///
    /// **Ne remplace jamais un profil que l'utilisateur a commencé à
    /// renseigner.** Cette méthode est appelée à chaque import CloudKit, y
    /// compris pendant l'onboarding : adopter alors la ligne venue d'iCloud
    /// substituerait l'objet sous les doigts de l'utilisateur, et ses
    /// saisies seraient remplacées par celles de la sauvegarde. Tant que le
    /// profil courant n'est pas un brouillon intact, il reste maître.
    private func adopterMeilleureLigne() {
        guard let modelContext else { return }
        let lignes = (try? modelContext.fetch(FetchDescriptor<ProfilUtilisateur>())) ?? []
        guard let canonique = Self.meilleure(parmi: lignes) else { return }

        if canonique.id != profil.id, estBrouillonVide(profil) {
            // Le brouillon local intact laisse la place au vrai profil. S'il
            // était déjà inséré, il part avec — inutile de laisser une ligne
            // neutre voyager sur iCloud.
            if profil.modelContext != nil {
                modelContext.delete(profil)
            }
            profil = canonique
        }

        // Purge des doublons vides restants (lignes créées par une version
        // précédente de l'app, ou par un autre appareil au même moment) —
        // seulement quand ils ne sont pas la ligne canonique.
        for ligne in lignes where ligne.id != canonique.id && estBrouillonVide(ligne) {
            modelContext.delete(ligne)
        }

        try? modelContext.save()
    }

    /// Ligne jamais renseignée par l'utilisateur — sûre à supprimer.
    private func estBrouillonVide(_ ligne: ProfilUtilisateur) -> Bool {
        !ligne.estValide
            && ligne.prenom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ligne.poidsKg == nil
            && ligne.photoData == nil
    }

    /// Départage entre plusieurs lignes profil. **Un profil valide gagne
    /// toujours contre un profil vide**, quelle que soit la date : c'était
    /// le bug historique (la ligne vide créée à l'instant écrasait le vrai
    /// profil importé d'iCloud, plus ancien). À validité égale, la plus
    /// récemment modifiée gagne.
    private static func meilleure(parmi lignes: [ProfilUtilisateur]) -> ProfilUtilisateur? {
        lignes.max { a, b in
            if a.estValide != b.estValide { return !a.estValide }
            return a.derniereMiseAJour < b.derniereMiseAJour
        }
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
        profil.derniereMiseAJour = Date()
        // Matérialisation tardive : `demarrer(contexte:)` n'insère rien
        // quand le store est vide, pour ne pas fabriquer un brouillon qui
        // partirait vers iCloud et gagnerait le départage contre le vrai
        // profil importé plus tard. La ligne n'existe donc en base qu'à
        // partir de la première saisie réelle — ici.
        if let modelContext, profil.modelContext == nil {
            modelContext.insert(profil)
        }
        sauvegarder()
    }

    /// Définit (ou retire si `nil`) la photo de profil, puis persiste.
    /// Raccourci sémantique au-dessus de `mettreAJour` pour l'avatar.
    func definirPhotoProfil(_ data: Data?) {
        mettreAJour { $0.photoData = data }
    }

    /// Réinitialise le profil aux valeurs par défaut (bouton « Supprimer
    /// les données et réglages » de la page Données). Réapplique les
    /// valeurs par défaut sur la ligne existante plutôt que de la
    /// remplacer — garde `id` stable et la ligne suivie par SwiftData.
    func reinitialiser() {
        profil.appliquer(depuis: .parDefaut())
        sauvegarder()
    }

    private func sauvegarder() {
        do {
            try modelContext?.save()
        } catch {
            // Échec d'écriture SwiftData — on log seulement, sans casser
            // l'UI. Le prochain `mettreAJour` retentera.
            print("ProfilService: sauvegarde échouée (\(error)).")
        }
    }
}

// MARK: - Mocks pour previews

extension ProfilService {

    /// Container SwiftData in-memory isolé pour les previews — évite toute
    /// interférence avec le vrai profil de l'utilisateur.
    private static func conteneurMock() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: ProfilUtilisateur.self, configurations: config)
    }

    /// Construit un service de preview pré-rempli avec `profil`, inséré
    /// dans un container in-memory avant `demarrer` — `demarrer` le
    /// retrouve alors comme unique ligne existante.
    private static func service(preRempli profil: ProfilUtilisateur) -> ProfilService {
        let contexte = conteneurMock().mainContext
        contexte.insert(profil)
        try? contexte.save()
        let service = ProfilService()
        service.demarrer(contexte: contexte)
        return service
    }

    /// Profil entièrement renseigné, mode ratio unique — utilisé pour
    /// le scénario par défaut « utilisateur déjà configuré ».
    static func mockComplet() -> ProfilService {
        service(preRempli: ProfilUtilisateur(
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
        ))
    }

    /// Profil entièrement renseigné, mode ratio par moment — pour
    /// vérifier l'affichage des 4 lignes de ratios.
    static func mockAvecRatiosParMoment() -> ProfilService {
        service(preRempli: ProfilUtilisateur(
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
            preferencesAvancees: PreferencesAvancees()
        ))
    }

    /// Profil au tout premier démarrage — tous les champs requis sont
    /// vides pour permettre de visualiser les erreurs « Requis » dans
    /// la sheet.
    static func mockVide() -> ProfilService {
        service(preRempli: .parDefaut())
    }
}
