//
//  diavizApp.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI
import SwiftData

@main
struct DiavizApp: App {
    /// Hub d'événements SwiftData. Toutes les entités du hub sont modélisées et
    /// enregistrées d'un bloc (évite les migrations de schéma ultérieures), même
    /// si la saisie de certaines (état, médicament, pause) n'est pas encore
    /// branchée. L'écriture réelle migre depuis les services mock étape par étape.
    ///
    /// Container explicite (pas le raccourci `.modelContainer(for:)`) : le sync
    /// CloudKit exige de choisir `cloudKitDatabase` sur la configuration, ce que
    /// le raccourci ne permet pas. `.automatic` réutilise le container iCloud
    /// déclaré dans les entitlements (`iCloud.fr.al3xdre.diaviz`) sans dupliquer
    /// son identifiant ici.
    ///
    /// Chaque `@Model` du hub respecte les contraintes CloudKit (aucun
    /// `@Attribute(.unique)`, toute propriété stockée optionnelle ou par
    /// défaut) — voir les commentaires sur `GlucoseReading` pour le détail.
    static let modelContainer: ModelContainer = {
        let schema = Schema([
            GlucoseReading.self,
            Injection.self,
            Repas.self,
            Aliment.self,
            ActiviteSportive.self,
            EtatDeclare.self,
            Medicament.self,
            PeriodePause.self,
            Resucrage.self,
        ])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Impossible de créer le ModelContainer : \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppTabVues()
                // App mono-utilisateur en français : on force la locale
                // fr_FR pour toute l'app (date pickers, formats de date,
                // etc.) au lieu de dépendre de la langue du device.
                .environment(\.locale, Locale(identifier: "fr_FR"))
        }
        .modelContainer(Self.modelContainer)
    }
}
