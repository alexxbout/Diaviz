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
    var body: some Scene {
        WindowGroup {
            AppTabVues()
        }
        .modelContainer(for: [
            GlucoseReading.self,
            Injection.self,
            Repas.self,
            Aliment.self,
            ActiviteSportive.self,
            EtatDeclare.self,
            Medicament.self,
            PeriodePause.self,
        ])
    }
}
