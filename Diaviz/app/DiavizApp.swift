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
    /// Hub d'événements SwiftData. V1 : seule `GlucoseReading` est persistée
    /// (ingestion Dexcom). Les autres entités du hub (Injection, Repas, …)
    /// migreront depuis les services mock au fur et à mesure.
    var body: some Scene {
        WindowGroup {
            AppTabVues()
        }
        .modelContainer(for: GlucoseReading.self)
    }
}
