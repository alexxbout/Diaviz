//
//  FiltreCoucher.swift
//  diaviz
//

import Foundation

// MARK: - Critère de similarité

/// Un critère de contexte activable dans la recherche « Comparer à ce soir ».
///
/// Chaque critère est ancré sur **ce soir** : il ne demande pas « y a-t-il eu
/// du sport ? » mais « ce soir-là ressemblait-il à ce soir sur ce point ? ».
/// D'où les valeurs associées — un soir sans sport se compare aux soirs sans
/// sport, pas l'inverse.
///
/// Volontairement binaire et énumérable : aucun score, aucune pondération.
/// L'utilisateur voit exactement ce qu'il compare.
nonisolated enum CritereCoucher: Hashable, Sendable, Identifiable {

    /// Présence (ou absence) d'une séance le jour même.
    case sport(present: Bool)
    /// Même type de séance (« Course », « Vélo »…). Proposé seulement quand
    /// une séance a eu lieu ce soir — sinon il n'y a rien à égaler.
    case typeSport(String)
    /// Même niveau de charge active.
    case charge(NiveauChargeActive)
    /// Présence (ou absence) d'insuline rapide encore active.
    case insuline(active: Bool)

    var id: String {
        switch self {
        case .sport(let present):   return "sport-\(present)"
        case .typeSport(let type):  return "type-\(type)"
        case .charge(let charge):   return "charge-\(charge.rawValue)"
        case .insuline(let active): return "iob-\(active)"
        }
    }

    var libelle: String {
        switch self {
        case .sport(true):          return "sport le jour"
        case .sport(false):         return "jour sans sport"
        case .typeSport(let type):  return type
        case .charge(let charge):   return charge.libelle
        case .insuline(true):       return "insuline active"
        case .insuline(false):      return "sans insuline active"
        }
    }

    var symbole: String {
        switch self {
        case .sport, .typeSport: return "figure.run"
        case .charge:            return "flame.fill"
        case .insuline:          return "bolt.fill"
        }
    }

    /// Ce soir passé correspond-il au critère ?
    func correspond(_ soir: SoirCoucher) -> Bool {
        switch self {
        case .sport(let present):   return (soir.sport != nil) == present
        case .typeSport(let type):  return soir.sport?.type == type
        case .charge(let charge):   return soir.charge == charge
        case .insuline(let active): return (soir.iob != nil) == active
        }
    }
}

// MARK: - Filtrage

/// Filtrage par critères de contexte de la recherche « Comparer à ce soir ».
///
/// Les critères se combinent en **ET** : chaque ajout rétrécit le corpus. Avec
/// ~60 nuits d'historique, c'est précisément le risque — d'où
/// `compteSiAjoute(_:)`, qui permet à l'UI d'afficher sur chaque critère le
/// nombre de soirs qui **resteraient** s'il était activé. L'utilisateur voit
/// le coût du critère avant de le poser, au lieu de tomber sur une liste vide
/// sans savoir lequel l'a vidée.
nonisolated enum FiltreCoucher {

    /// Critères proposables pour le contexte de ce soir, dans l'ordre
    /// d'affichage. Le type de sport n'apparaît que si une séance a eu lieu.
    static func criteres(
        charge: NiveauChargeActive?,
        sport: SportResume?,
        iob: Double?
    ) -> [CritereCoucher] {
        var liste: [CritereCoucher] = [.sport(present: sport != nil)]
        if let type = sport?.type, !type.isEmpty {
            liste.append(.typeSport(type))
        }
        if let charge { liste.append(.charge(charge)) }
        liste.append(.insuline(active: iob != nil))
        return liste
    }

    /// Soirs satisfaisant **tous** les critères actifs. Ensemble vide → tout
    /// passe (la bande de glycémie reste le seul filtre).
    static func filtrer(
        _ soirs: [SoirCoucher], par criteres: Set<CritereCoucher>
    ) -> [SoirCoucher] {
        guard !criteres.isEmpty else { return soirs }
        return soirs.filter { soir in
            criteres.allSatisfy { $0.correspond(soir) }
        }
    }

    /// Nombre de soirs restants si `critere` s'ajoutait aux critères actifs.
    /// Pour un critère déjà actif, c'est simplement l'effectif courant.
    static func compteSiAjoute(
        _ critere: CritereCoucher,
        dans soirs: [SoirCoucher],
        criteres actifs: Set<CritereCoucher>
    ) -> Int {
        filtrer(soirs, par: actifs.union([critere])).count
    }
}
