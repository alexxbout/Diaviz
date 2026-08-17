//
//  SuppressionDonneesService.swift
//  diaviz
//

import Foundation
import SwiftData

/// Suppression du contenu du store local. Les suppressions se propagent
/// d'elles-mêmes à iCloud ; effacer directement le stockage distant relève
/// de `SyncICloudService.supprimerZone()`.
///
/// Existe pour une raison précise : `ModelContext.delete(model:)` est un
/// *batch delete*. Il vide bien le store local, mais contourne le contexte
/// — il ne génère donc aucun historique de transaction, et
/// `NSPersistentCloudKitContainer` n'a rien à exporter. Résultat observé :
/// les données réapparaissaient au lancement suivant, ré-importées depuis
/// iCloud qui ne les avait jamais vues disparaître.
///
/// Ici tout passe par des suppressions objet par objet via le contexte :
/// plus lent, mais c'est la seule forme que CloudKit propage.
enum SuppressionDonneesService {

    /// Types du hub effacés par « Supprimer les données ». `GlucoseReading`
    /// est volontairement absent : c'est la donnée source venant d'Apple
    /// Santé, non ressaisissable, et ré-importable à tout moment.
    /// `ProfilUtilisateur` est traité à part (via `ProfilService`).
    ///
    /// `Aliment` n'apparaît pas non plus : ses lignes sont supprimées en
    /// cascade par leurs parents (`Repas`, `Resucrage`, `ActiviteSportive`)
    /// grâce aux `@Relationship(deleteRule: .cascade)`. Les supprimer
    /// séparément d'abord priverait la cascade de ses objets et laisserait
    /// des relations incohérentes à exporter.
    @MainActor
    static func supprimerDonneesHub(contexte: ModelContext) {
        supprimerToutes(Repas.self, contexte: contexte)
        supprimerToutes(Resucrage.self, contexte: contexte)
        supprimerToutes(ActiviteSportive.self, contexte: contexte)
        supprimerToutes(Injection.self, contexte: contexte)
        supprimerToutes(EtatDeclare.self, contexte: contexte)
        supprimerToutes(Medicament.self, contexte: contexte)
        supprimerToutes(PeriodePause.self, contexte: contexte)
        // Filet de sécurité : d'éventuels `Aliment` orphelins (sans parent,
        // donc jamais atteints par une cascade) partent aussi.
        supprimerToutes(Aliment.self, contexte: contexte)
        try? contexte.save()
    }

    /// Ajoute les glycémies à la suppression — réservé au reset complet
    /// (« repartir de zéro »), où l'on veut réellement un compte iCloud
    /// vierge. Elles se ré-importeront d'Apple Santé au prochain démarrage.
    @MainActor
    static func supprimerGlycemies(contexte: ModelContext) {
        supprimerToutes(GlucoseReading.self, contexte: contexte)
        try? contexte.save()
    }

    /// Supprime toutes les lignes profil, y compris les doublons éventuels.
    @MainActor
    static func supprimerProfils(contexte: ModelContext) {
        supprimerToutes(ProfilUtilisateur.self, contexte: contexte)
        try? contexte.save()
    }

    /// Supprime les préférences d'usage (renommages, masquages, aliments
    /// récents, contextes normalisés) et vide les caches mémoire des services
    /// correspondants — sans quoi ils continueraient d'afficher un état qui
    /// n'existe plus en base, jusqu'au prochain lancement.
    @MainActor
    static func supprimerPreferences(contexte: ModelContext) {
        supprimerToutes(PreferenceAlimentCiqual.self, contexte: contexte)
        supprimerToutes(AlimentRecentEnregistre.self, contexte: contexte)
        supprimerToutes(ContexteNormaliseEnregistre.self, contexte: contexte)
        supprimerToutes(RepasARevoirMasque.self, contexte: contexte)
        try? contexte.save()

        NomsPersonnalisesService.shared.recharger()
        AlimentsCachesService.shared.recharger()
        AlimentsRecentsService.shared.recharger()
        RepasARevoirMasquesService.shared.recharger()
        ReferentielContextesService.shared.recharger()
    }

    /// Suppression objet par objet — la seule que CloudKit exporte.
    @MainActor
    private static func supprimerToutes<T: PersistentModel>(
        _ type: T.Type,
        contexte: ModelContext
    ) {
        let objets = (try? contexte.fetch(FetchDescriptor<T>())) ?? []
        for objet in objets {
            contexte.delete(objet)
        }
    }

    /// Efface l'intégralité du contenu local : données du hub, glycémies,
    /// profil et préférences. Utilisé par la réinitialisation complète, par
    /// « repartir de zéro » à la restauration, et avant un import d'archive
    /// — les trois voulaient exactement la même chose et le réécrivaient
    /// chacun de leur côté.
    ///
    /// Ne touche pas à iCloud : voir `SyncICloudService.supprimerZone()`,
    /// à appeler ensuite quand on veut aussi un compte vierge.
    @MainActor
    static func supprimerTout(contexte: ModelContext) {
        supprimerDonneesHub(contexte: contexte)
        supprimerGlycemies(contexte: contexte)
        supprimerProfils(contexte: contexte)
        supprimerPreferences(contexte: contexte)
    }
}
