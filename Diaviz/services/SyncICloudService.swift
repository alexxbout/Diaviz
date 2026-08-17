//
//  SyncICloudService.swift
//  diaviz
//

import CloudKit
import CoreData
import Foundation
import Observation

/// Suit l'activité de synchronisation CloudKit et l'expose à l'UI.
///
/// Aucune API ne permet de déclencher une synchronisation, ni de savoir ce
/// qui reste en attente d'envoi (confirmé par Apple DTS). Le seul signal
/// disponible est le flux d'événements de `NSPersistentCloudKitContainer` :
/// ce service le capte et en garde la trace, pour donner à l'utilisateur une
/// réponse honnête à « est-ce que mes données sont bien sauvegardées ? ».
///
/// Les échecs sont conservés au même titre que les succès. Une version
/// antérieure ne retenait que les événements réussis : un export en erreur
/// ne produisait alors *aucune* trace, indiscernable d'un « rien à envoyer »
/// — exactement le cas où l'information est vitale.
@Observable
@MainActor
final class SyncICloudService {

    static let shared = SyncICloudService()

    // MARK: - État observable

    /// Activité en cours (`nil` quand rien ne tourne).
    private(set) var activiteEnCours: TypeActivite?

    /// Dernier envoi vers iCloud terminé avec succès.
    private(set) var dernierExport: Date?

    /// Dernière réception depuis iCloud terminée avec succès.
    private(set) var dernierImport: Date?

    /// Dernier échec rencontré, avec son horodatage. Conservé jusqu'au
    /// prochain succès du même type.
    private(set) var derniereErreur: (date: Date, message: String)?

    enum TypeActivite {
        case miseEnPlace
        case reception
        case envoi

        var libelle: String {
            switch self {
            case .miseEnPlace: "Mise en place…"
            case .reception: "Réception en cours…"
            case .envoi: "Envoi en cours…"
            }
        }
    }

    // MARK: - Persistance des horodatages

    private static let cleExport = "sync.icloud.dernierExport"
    private static let cleImport = "sync.icloud.dernierImport"

    private init() {
        let stockage = UserDefaults.standard
        let export = stockage.double(forKey: Self.cleExport)
        let importe = stockage.double(forKey: Self.cleImport)
        dernierExport = export > 0 ? Date(timeIntervalSince1970: export) : nil
        dernierImport = importe > 0 ? Date(timeIntervalSince1970: importe) : nil
    }

    // MARK: - Observation

    /// Boucle d'observation, à lancer une fois depuis la vue racine. Ne rend
    /// jamais la main : elle vit aussi longtemps que l'app.
    ///
    /// `onImportReussi` est appelé à chaque réception aboutie — c'est le
    /// moment où les services doivent relire le store, sans quoi les données
    /// venues d'un autre appareil resteraient invisibles.
    func observer(onImportReussi: @escaping () -> Void) async {
        for await notification in NotificationCenter.default.notifications(
            named: NSPersistentCloudKitContainer.eventChangedNotification
        ) {
            guard let evenement = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { continue }

            traiter(evenement, onImportReussi: onImportReussi)
        }
    }

    private func traiter(
        _ evenement: NSPersistentCloudKitContainer.Event,
        onImportReussi: () -> Void
    ) {
        let type = Self.activite(pour: evenement.type)

        // `endDate == nil` : l'événement vient de démarrer. C'est ce qui
        // alimente l'indicateur d'activité — sans lui, l'utilisateur n'aurait
        // aucun signe que la synchronisation travaille.
        guard evenement.endDate != nil else {
            activiteEnCours = type
            return
        }

        activiteEnCours = nil

        if let erreur = evenement.error {
            derniereErreur = (Date(), erreur.localizedDescription)
            return
        }

        guard evenement.succeeded else { return }
        derniereErreur = nil

        switch evenement.type {
        case .export:
            dernierExport = Date()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cleExport)
        case .import:
            dernierImport = Date()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cleImport)
            onImportReussi()
        default:
            break
        }
    }

    private static func activite(
        pour type: NSPersistentCloudKitContainer.EventType
    ) -> TypeActivite {
        switch type {
        case .setup: .miseEnPlace
        case .import: .reception
        case .export: .envoi
        @unknown default: .miseEnPlace
        }
    }

    // MARK: - Interrogation directe du serveur

    /// Identifiant du container iCloud, déclaré dans `Diaviz.entitlements`.
    static let identifiantContainer = "iCloud.fr.al3xdre.diaviz"

    /// Zone créée et utilisée par `NSPersistentCloudKitContainer` pour tout
    /// le stockage miroir de SwiftData. Nom fixé par Apple.
    private static let nomZoneCoreData = "com.apple.coredata.cloudkit.zone"

    /// Réponse d'iCloud à la question « ce compte a-t-il déjà des données ? ».
    enum EtatDonnees {
        /// La zone existe : l'app a déjà stocké des données sur ce compte.
        case presentes
        /// Compte joignable, aucune zone : rien n'a jamais été stocké.
        case vide
        /// Compte indisponible ou réseau injoignable — on ne sait pas, et il
        /// ne faut surtout pas conclure « vide » (l'utilisateur repartirait
        /// de zéro alors que ses données existent).
        case indetermine
    }

    /// Demande **directement au serveur** si l'app a déjà des données sur ce
    /// compte, en vérifiant l'existence de la zone Core Data.
    ///
    /// Interroger CloudKit plutôt que d'attendre que SwiftData veuille bien
    /// importer : l'événement d'import est un signal indirect et prématuré
    /// (le premier arrive souvent vide, à la mise en place du store), et il
    /// n'existe aucune API pour savoir quand la synchronisation est
    /// réellement terminée. Ici la réponse est immédiate et sans ambiguïté.
    ///
    /// La zone peut exister tout en étant vide (données supprimées sans
    /// suppression de la zone) — le cas est traité comme « présentes » à
    /// dessein : mieux vaut proposer un choix inutile que d'effacer
    /// silencieusement un historique.
    static func interrogerDonneesICloud() async -> EtatDonnees {
        let container = CKContainer(identifier: identifiantContainer)

        guard let statut = try? await container.accountStatus(), statut == .available else {
            return .indetermine
        }

        do {
            _ = try await container.privateCloudDatabase.recordZone(for: zoneCoreData)
            return .presentes
        } catch let erreur as CKError where erreur.code == .zoneNotFound || erreur.code == .unknownItem {
            return .vide
        } catch {
            return .indetermine
        }
    }

    /// État du compte iCloud — sert à expliquer honnêtement pourquoi une
    /// synchronisation ne se fait pas, plutôt que de laisser croire à un bug.
    static func statutCompte() async -> CKAccountStatus {
        (try? await CKContainer(identifier: identifiantContainer).accountStatus()) ?? .couldNotDetermine
    }

    /// Efface d'un coup **tout** ce que l'app a stocké dans iCloud, en
    /// supprimant directement la zone CloudKit.
    ///
    /// Pourquoi ne pas se contenter des suppressions locales : celles-ci ne
    /// partent vers iCloud que lorsque l'export s'exécute, ce qui n'est ni
    /// immédiat ni garanti pendant qu'on regarde. Supprimer la zone est
    /// instantané côté serveur et sans ambiguïté — c'est l'équivalent réel
    /// de « supprimer les données de l'app » dans Réglages iOS, qui reste
    /// souvent sans effet visible sur l'environnement de développement
    /// utilisé par un build Xcode.
    ///
    /// L'app doit être relancée derrière : le store local garde des
    /// métadonnées de synchronisation qui pointent vers une zone désormais
    /// absente.
    static func supprimerZone() async throws {
        let base = CKContainer(identifier: identifiantContainer).privateCloudDatabase
        do {
            _ = try await base.deleteRecordZone(withID: zoneCoreData)
        } catch let erreur as CKError where erreur.code == .zoneNotFound {
            // Déjà vide : rien à faire, ce n'est pas un échec.
            return
        }
    }

    private static var zoneCoreData: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: nomZoneCoreData, ownerName: CKCurrentUserDefaultName)
    }
}
