//
//  EstEncoreDansLeHubTests.swift
//  DiavizTests
//

import Foundation
import SwiftData
import Testing
@testable import Diaviz

@MainActor
struct EstEncoreDansLeHubTests {

    private func conteneur() throws -> ModelContainer {
        try ModelContainer(for: GlucoseReading.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func vraiTantQueLObjetExiste() throws {
        let contexte = ModelContext(try conteneur())
        let lecture = GlucoseReading(date: Date(), valeur: 100, source: .healthkit)
        contexte.insert(lecture)
        try contexte.save()
        #expect(lecture.estEncoreDansLeHub)
    }

    @Test func fauxDesLaSuppressionAvantEnregistrement() throws {
        let contexte = ModelContext(try conteneur())
        let lecture = GlucoseReading(date: Date(), valeur: 100, source: .healthkit)
        contexte.insert(lecture)
        try contexte.save()
        contexte.delete(lecture)
        #expect(!lecture.estEncoreDansLeHub)
    }

    @Test func fauxApresEnregistrementDeLaSuppression() throws {
        let contexte = ModelContext(try conteneur())
        let lecture = GlucoseReading(date: Date(), valeur: 100, source: .healthkit)
        contexte.insert(lecture)
        try contexte.save()
        contexte.delete(lecture)
        try contexte.save()
        #expect(!lecture.estEncoreDansLeHub)
    }
}
