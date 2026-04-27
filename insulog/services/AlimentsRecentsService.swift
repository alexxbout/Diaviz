//
//  AlimentsRecentsService.swift
//  insulog
//
//  Created by Alexandre on 27/04/2026.
//

import Foundation

@Observable
final class AlimentsRecentsService {
    static let shared = AlimentsRecentsService()

    private let cleStockage = "alimentsRecents"
    private let limiteRecents = 50

    private(set) var idsRecents: [Int] = []

    private init() {
        charger()
    }

    func marquerUtilise(_ aliment: AlimentCiqual) {
        idsRecents.removeAll { $0 == aliment.id }
        idsRecents.insert(aliment.id, at: 0)
        if idsRecents.count > limiteRecents {
            idsRecents = Array(idsRecents.prefix(limiteRecents))
        }
        sauvegarder()
    }

    func estRecent(_ aliment: AlimentCiqual) -> Bool {
        idsRecents.contains(aliment.id)
    }

    func position(_ aliment: AlimentCiqual) -> Int? {
        idsRecents.firstIndex(of: aliment.id)
    }

    var alimentsRecents: [AlimentCiqual] {
        idsRecents.compactMap { id in
            CiqualService.shared.aliments.first { $0.id == id }
        }
    }

    func effacer() {
        idsRecents = []
        UserDefaults.standard.removeObject(forKey: cleStockage)
    }

    private func charger() {
        if let data = UserDefaults.standard.array(forKey: cleStockage) as? [Int] {
            idsRecents = data
        }
    }

    private func sauvegarder() {
        UserDefaults.standard.set(idsRecents, forKey: cleStockage)
    }
}
