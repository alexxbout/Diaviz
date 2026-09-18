//
//  CalculInventaireDonnees.swift
//  diaviz
//

import Foundation

// MARK: - Entrées

/// Un fait horodaté réduit à ce que l'inventaire compte : sa date, son
/// domaine, et la grandeur cumulable qui a un sens pour lui.
///
/// Value type volontairement pauvre : l'inventaire n'a aucun besoin des
/// `@Model` complets, et rester découplé de SwiftData rend le calcul
/// testable — même pattern qu'`EntreeRatioRepas` ou `EntreesBasale`.
nonisolated struct EntreeInventaire: Sendable, Equatable {
    enum Domaine: Sendable, Equatable {
        case repas(glucides: Int)
        case injection(unites: Double, lente: Bool)
        case sport(minutes: Int)
        case resucrage(preventif: Bool)
    }

    let date: Date
    let domaine: Domaine
}

// MARK: - Résultat

nonisolated struct PointSaisieJour: Sendable, Equatable, Identifiable {
    let jour: Date
    /// Nombre d'enregistrements ce jour-là, toutes familles confondues.
    let saisies: Int
    var id: Date { jour }
}

nonisolated struct InventaireDonnees: Sendable, Equatable {
    /// Date du plus ancien fait saisi — `nil` si le hub est vide. Les
    /// glycémies n'entrent pas dans ce calcul : elles viennent d'Apple Santé
    /// et remontent souvent bien avant la première utilisation de l'app.
    let premiereSaisie: Date?
    /// Jours écoulés depuis cette première saisie, aujourd'hui compris.
    let joursCouverts: Int

    /// Mesures CGM présentes dans le hub — importées d'Apple Santé, jamais
    /// saisies à la main, d'où leur absence du calcul d'ancienneté.
    let glycemies: Int

    let repas: Int
    let glucidesTotal: Int
    let joursAvecRepas: Int

    let injections: Int
    let injectionsLentes: Int
    let unitesTotal: Double

    let seances: Int
    let minutesSport: Int

    let resucrages: Int
    let resucragesPreventifs: Int

    /// Densité de saisie des 14 derniers jours, du plus ancien au plus
    /// récent — toujours 14 points, les jours sans rien à 0.
    let saisiesParJour: [PointSaisieJour]

    /// Jours consécutifs, jusqu'à aujourd'hui inclus, avec au moins une
    /// saisie manuelle (repas, injection, sport, resucrage — jamais le CGM,
    /// qui arrive seul depuis Apple Santé). Un jour sans saisie ne casse le
    /// streak que s'il est déjà passé : tant qu'on est dans la journée en
    /// cours, le streak d'hier reste affiché.
    let streakActuel: Int
    /// Plus longue série jamais atteinte, tous historiques confondus.
    let streakRecord: Int

    var injectionsRapides: Int { injections - injectionsLentes }
    var resucragesCorrectifs: Int { resucrages - resucragesPreventifs }

    /// Vrai quand rien n'a jamais été saisi : la page affiche alors son état
    /// vide plutôt qu'une colonne de zéros.
    var estVide: Bool { premiereSaisie == nil }
}

// MARK: - Calculateur

/// Inventaire de ce que contient le hub — combien de repas, d'injections, de
/// séances, de resucrages, et depuis quand.
///
/// **Ce n'est pas une analyse de santé** : aucun de ces chiffres n'est
/// confronté à un seuil ni jugé. Il s'agit de décrire le corpus, notamment
/// pour comprendre pourquoi une analyse reste muette — « 41 repas sur 13
/// jours » explique mieux qu'un message d'attente.
///
/// Les glycémies sont passées à part (`nombreGlycemies`) : elles se comptent
/// par milliers, les charger pour les dénombrer serait absurde là où
/// `fetchCount` suffit.
nonisolated enum CalculInventaireDonnees {

    /// Fenêtre de la trame de régularité.
    static let joursTrame = 14

    static func analyser(
        entrees: [EntreeInventaire],
        nombreGlycemies: Int,
        maintenant: Date = Date(),
        calendrier: Calendar = .current
    ) -> InventaireDonnees {
        let aujourdhui = calendrier.startOfDay(for: maintenant)

        var glucides = 0, unites = 0.0, minutes = 0
        var repas = 0, injections = 0, lentes = 0, seances = 0, resucrages = 0, preventifs = 0
        var joursAvecRepas: Set<Date> = []
        var saisiesParJour: [Date: Int] = [:]
        var premiere: Date?

        for entree in entrees {
            let jour = calendrier.startOfDay(for: entree.date)
            saisiesParJour[jour, default: 0] += 1
            if premiere == nil || entree.date < premiere! { premiere = entree.date }

            switch entree.domaine {
            case .repas(let g):
                repas += 1
                glucides += g
                joursAvecRepas.insert(jour)
            case .injection(let u, let estLente):
                injections += 1
                unites += u
                if estLente { lentes += 1 }
            case .sport(let m):
                seances += 1
                minutes += m
            case .resucrage(let estPreventif):
                resucrages += 1
                if estPreventif { preventifs += 1 }
            }
        }

        let trame: [PointSaisieJour] = (0..<joursTrame).compactMap { offset in
            guard let jour = calendrier.date(byAdding: .day, value: -(joursTrame - 1 - offset), to: aujourdhui)
            else { return nil }
            return PointSaisieJour(jour: jour, saisies: saisiesParJour[jour] ?? 0)
        }

        let joursAvecSaisie = Set(saisiesParJour.keys)
        let (streakActuel, streakRecord) = streaks(joursAvecSaisie: joursAvecSaisie, aujourdhui: aujourdhui, calendrier: calendrier)

        return InventaireDonnees(
            premiereSaisie: premiere,
            joursCouverts: premiere.map { jours(de: $0, a: aujourdhui, calendrier: calendrier) } ?? 0,
            glycemies: nombreGlycemies,
            repas: repas,
            glucidesTotal: glucides,
            joursAvecRepas: joursAvecRepas.count,
            injections: injections,
            injectionsLentes: lentes,
            unitesTotal: unites,
            seances: seances,
            minutesSport: minutes,
            resucrages: resucrages,
            resucragesPreventifs: preventifs,
            saisiesParJour: trame,
            streakActuel: streakActuel,
            streakRecord: streakRecord
        )
    }

    /// Streak courant (recule depuis aujourd'hui, ou hier si rien n'est
    /// encore saisi aujourd'hui) et record historique (plus longue série
    /// consécutive dans tout le corpus).
    private static func streaks(
        joursAvecSaisie: Set<Date>,
        aujourdhui: Date,
        calendrier: Calendar
    ) -> (actuel: Int, record: Int) {
        guard !joursAvecSaisie.isEmpty else { return (0, 0) }

        var actuel = 0
        var jour = joursAvecSaisie.contains(aujourdhui)
            ? aujourdhui
            : calendrier.date(byAdding: .day, value: -1, to: aujourdhui) ?? aujourdhui
        while joursAvecSaisie.contains(jour) {
            actuel += 1
            guard let precedent = calendrier.date(byAdding: .day, value: -1, to: jour) else { break }
            jour = precedent
        }

        var record = 0, courant = 0
        var precedent: Date?
        for j in joursAvecSaisie.sorted() {
            if let p = precedent, calendrier.date(byAdding: .day, value: 1, to: p) == j {
                courant += 1
            } else {
                courant = 1
            }
            record = max(record, courant)
            precedent = j
        }

        return (actuel, record)
    }

    /// Jours **inclusifs** entre deux dates : une première saisie datée
    /// d'aujourd'hui couvre 1 jour, pas 0.
    private static func jours(de debut: Date, a fin: Date, calendrier: Calendar) -> Int {
        let depuis = calendrier.startOfDay(for: debut)
        let ecart = calendrier.dateComponents([.day], from: depuis, to: fin).day ?? 0
        return max(1, ecart + 1)
    }
}
