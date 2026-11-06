//
//  LecteursSanteDemo.swift
//  diaviz
//
//  Remplaçants d'Apple Santé pour l'app « Diaviz Démo » : mêmes méthodes que
//  `HealthKitChargeActiveLecteur` et `HealthKitSleepService`, alimentées par
//  le jeu fictif. Compilés uniquement avec la condition `DEMO` : la vraie
//  app n'en contient pas une ligne.
//

#if DEMO
import Foundation
import SwiftData

/// Faits « Santé » du jeu démo, posés une fois au lancement par
/// `DemarrageDemo.preparer`, avant le démarrage des services.
nonisolated enum SanteDemo {
    nonisolated(unsafe) static var faits: FaitsSanteDemo?
}

/// Remplaçant de `HealthKitChargeActiveLecteur` (pas, marche, séances, FC).
nonisolated struct LecteurChargeDemo: Sendable {

    func demanderAcces() async {}

    func autorisationTranchee() async -> Bool { SanteDemo.faits != nil }

    func premierPas(borne: Date) async -> Date? { SanteDemo.faits?.debut }

    func pasParBloc(sur intervalle: DateInterval, calendrier: Calendar = .current) async -> [PasBloc] {
        let debut = calendrier.dateInterval(of: .hour, for: intervalle.start)?.start ?? intervalle.start
        return sommes(de: debut, a: intervalle.end, minutes: CalculChargeActive.dureeBlocMinutes)
            .map { PasBloc(debut: $0.debut, pas: $0.pas) }
    }

    func pasParMinute(plages: [DateInterval], parallelisme: Int = 4) async -> [PasMinute] {
        plages.flatMap { plage in
            sommes(de: plage.start, a: plage.end, minutes: 1).map { PasMinute(debut: $0.debut, pas: $0.pas) }
        }
    }

    func workouts(sur intervalle: DateInterval) async -> [WorkoutPourCharge] {
        (SanteDemo.faits?.workouts ?? []).filter { intervalle.intersects($0.intervalle) }
    }

    func picsSoutenus(seances: [WorkoutPourCharge], parallelisme: Int = 4) async -> [UUID: Double?] {
        let pics = SanteDemo.faits?.pics ?? [:]
        return Dictionary(uniqueKeysWithValues: seances.map { ($0.uuid, pics[$0.uuid]) })
    }

    private func sommes(de debut: Date, a fin: Date, minutes: Int) -> [(debut: Date, pas: Double)] {
        guard let faits = SanteDemo.faits, debut < fin else { return [] }
        var resultat: [(debut: Date, pas: Double)] = []
        var t = debut
        while t < fin {
            var somme = 0.0
            for m in 0..<minutes { somme += faits.pas(minute: t.addingTimeInterval(Double(m) * 60)) }
            if somme > 0 { resultat.append((t, somme)) }
            t = t.addingTimeInterval(Double(minutes) * 60)
        }
        return resultat
    }
}

/// Remplaçant de `HealthKitSleepService`.
@Observable
final class LecteurSommeilDemo {
    static var disponible: Bool { SanteDemo.faits != nil }

    func stades(sur plage: ClosedRange<Date>) async -> [SleepStageInterval] {
        guard let faits = SanteDemo.faits else { return [] }
        let debut = plage.lowerBound.addingTimeInterval(-3600)
        let fin = plage.upperBound.addingTimeInterval(3600)
        return faits.sommeil
            .filter { $0.fin > debut && $0.debut < fin }
            .map { SleepStageInterval(stage: $0.stade, debut: $0.debut, fin: $0.fin) }
    }
}

/// Préparation de l'app démo au lancement.
enum DemarrageDemo {

    /// Hub en mémoire, régénéré à chaque lancement : le jour en cours est
    /// toujours « aujourd'hui », et rien ne persiste.
    static func preparer(contexte: ModelContext) {
        // Caches dérivés de la charge active : recalculés depuis le jeu.
        for cle in ["chargeActive.cacheBoutsMarche.v1", "chargeActive.picsFCSeances.v1"] {
            UserDefaults.standard.removeObject(forKey: cle)
        }
        let jeu = GenerateurDemo.generer(ancre: Date())
        SanteDemo.faits = jeu.faitsSante
        jeu.inserer(dans: contexte)
    }
}
#endif
