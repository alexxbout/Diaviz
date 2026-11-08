//
//  ChargeurEpisodesCharge.swift
//  diaviz
//

import Foundation
import SwiftData

/// Traduit les faits du hub en événements jugés pour `CalculEpisodesCharge`
/// (C1 § 7) : une nuit B1 pour la lente, un repas R1 pour un ratio.
enum ChargeurEpisodesCharge {

    /// Date de livraison de l'enregistreur d'historique des paramètres
    /// (C1 § 2) : avant, la valeur d'un ratio changé n'est pas connue.
    static let debutEnregistreur: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 23
        return Calendar.current.date(from: c) ?? .distantPast
    }()

    // MARK: Réglages copiés du profil

    /// Copie des réglages du profil nécessaires aux événements de repas : le
    /// profil est un `@Model`, il ne quitte pas le thread principal.
    nonisolated struct ReglagesRepas: Sendable {
        let ratiosSport: RatiosSport
        let horaires: HorairesRepas
        let modeRatio: ModeRatio
        let valeursCourantes: [CleParametre: Double]
        let inconnueAvant: [MomentRatio: Date]
        let diaHeures: Double
        let picMinutes: Double
    }

    @MainActor
    static func reglagesRepas(profil: ProfilUtilisateur) -> ReglagesRepas {
        let moments: [MomentRatio] = [.unique, .matin, .midi, .gouter, .soir]
        return ReglagesRepas(
            ratiosSport: profil.ratiosSportEffectifs,
            horaires: profil.horairesRepas,
            modeRatio: profil.modeRatio,
            valeursCourantes: HistoriqueParametres.Instantane(profil: profil).valeurs,
            inconnueAvant: moments.reduce(into: [:]) { $0[$1] = inconnueAvant($1, profil: profil) },
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
    }

    // MARK: Lente — une nuit

    /// Une nuit B1 → un événement de lente. Nuit en cours et nuit sans lente
    /// écartées. Une hypo que l'insuline rapide active n'explique pas prime ;
    /// sinon le classement B1 (stable / tendance) fait foi ; sans classement,
    /// la nuit n'est pas évaluable.
    nonisolated static func evenementsNuits(_ nuits: [NightChartData]) -> [EvenementReglage] {
        nuits.compactMap { nuit in
            guard !nuit.enCours, nuit.basaleDose > 0 else { return nil }
            let issue: IssueEvenement
            if nuit.hyposNonExpliquees > 0 {
                issue = .hypo
            } else {
                switch nuit.categorieVerdict {
                case .stable:                       issue = .concluant
                case .tendanceBasse, .tendanceHaute: issue = .rate
                case nil:                           issue = .nonEvaluable
                }
            }
            return EvenementReglage(date: nuit.date, reglage: .lente, valeur: nuit.basaleDose, issue: issue)
        }
    }

    // MARK: Ratios — un repas

    /// Un repas jugé par R1 → un événement de ratio : le ratio du moment, ou
    /// le ratio sport du type de séance quand il était en vigueur. Repas
    /// retenus par la règle commune `CalculEligibiliteRepas` (la même que
    /// l'analyse des ratios), puis verdict disponible et dose non nulle ; le
    /// verdict `moyen` est non évaluable (C1 § 7).
    nonisolated static func evenementsRepas(
        _ contexte: ModelContext, depuis: Date, reglages: ReglagesRepas
    ) -> [EvenementReglage] {
        // Un jour de marge : un repas de la veille peut polluer la fenêtre
        // d'un repas du premier jour.
        let borneFaits = depuis.addingTimeInterval(-86_400)
        let repas = (try? contexte.fetch(FetchDescriptor<Repas>(predicate: #Predicate { $0.heure >= borneFaits }))) ?? []
        let activites = (try? contexte.fetch(FetchDescriptor<ActiviteSportive>())) ?? []
        let faits = AnalyseRatioService.faitsFenetre(
            repas: repas, contexte: contexte, activites: activites,
            diaHeures: reglages.diaHeures, picMinutes: reglages.picMinutes
        )
        let seancesSport = AnalyseRatioService.seancesRatioSport(activites, ratios: reglages.ratiosSport)
        let fenetreSport = reglages.ratiosSport.fenetreEffetHeures * 3600
        let changements = ((try? contexte.fetch(FetchDescriptor<ChangementParametre>())) ?? [])
            .compactMap { c in c.cle.map { (date: c.date, cle: $0, ancienne: c.ancienneValeur) } }
        let courantes = reglages.valeursCourantes

        return repas.compactMap { r -> EvenementReglage? in
            guard r.heure >= depuis else { return nil }
            let eligibilite = CalculEligibiliteRepas.evaluer(
                AnalyseRatioService.repasAJuger(r), faits: faits,
                seancesRatioSport: seancesSport, fenetreEffetSport: fenetreSport
            )
            guard eligibilite.estEligible else { return nil }
            guard let verdict = r.verdictPersiste, verdict != .indetermine, r.totalGlucides > 0 else { return nil }
            guard r.totalInsuline - (r.doseCorrection ?? 0) > 0 else { return nil }

            let issue: IssueEvenement
            switch verdict {
            case .bon:          issue = .concluant
            case .moyen:        issue = .nonEvaluable
            case .mauvais:      issue = r.raisonMauvaisPersistee == .hypoglycemie ? .hypo : .rate
            case .indetermine:  return nil
            }

            switch eligibilite.ratio {
            case .sport(let type):
                let cle = CleParametre(parametre: .ratioSport, typeSport: type)
                return EvenementReglage(
                    date: r.heure, reglage: .ratioSport(type),
                    valeur: valeur(a: r.heure, cle: cle, courante: courantes[cle], changements: changements, inconnueAvant: nil),
                    issue: issue
                )
            case .moment:
                let section = r.section(horaires: reglages.horaires)
                let moment = moment(section: section, modeRatio: reglages.modeRatio)
                let cle = CleParametre(parametre: parametre(moment))
                return EvenementReglage(
                    date: r.heure, reglage: .ratio(moment),
                    valeur: valeur(
                        a: r.heure, cle: cle, courante: courantes[cle], changements: changements,
                        inconnueAvant: reglages.inconnueAvant[moment]
                    ),
                    issue: issue
                )
            }
        }
    }

    /// Valeurs actuelles des ratios, depuis le profil (la lente vient des
    /// injections, ajoutée par l'appelant).
    static func valeursActuelles(profil: ProfilUtilisateur) -> [ReglageSuivi: Double] {
        var valeurs: [ReglageSuivi: Double] = [:]
        let courantes = HistoriqueParametres.Instantane(profil: profil).valeurs
        let moments: [MomentRatio] = profil.modeRatio == .unique ? [.unique] : [.matin, .midi, .gouter, .soir]
        for m in moments {
            if let v = courantes[CleParametre(parametre: parametre(m))], v > 0 { valeurs[.ratio(m)] = v }
        }
        for (type, ratio) in profil.ratiosSportEffectifs.parType where ratio > 0 {
            valeurs[.ratioSport(type)] = ratio
        }
        return valeurs
    }

    // MARK: Historique des valeurs

    /// Valeur d'un paramètre à une date : on part de la valeur courante et
    /// on remonte les changements postérieurs. `nil` avant `inconnueAvant`.
    nonisolated static func valeur(
        a date: Date,
        cle: CleParametre,
        courante: Double?,
        changements: [(date: Date, cle: CleParametre, ancienne: Double?)],
        inconnueAvant: Date?
    ) -> Double? {
        if let inconnueAvant, date < inconnueAvant { return nil }
        return changements
            .filter { $0.cle == cle && $0.date > date }
            .sorted { $0.date > $1.date }
            .reduce(courante) { _, changement in changement.ancienne }
    }

    /// Un ratio changé avant la livraison de l'enregistreur a une date de
    /// changement connue mais pas son ancienne valeur (C1 § 2).
    static func inconnueAvant(_ moment: MomentRatio, profil: ProfilUtilisateur) -> Date? {
        let dates = profil.datesChangementRatioEffectives
        let date: Date? = switch moment {
        case .unique: dates.unique
        case .matin:  dates.petitDejeuner
        case .midi:   dates.dejeuner
        case .gouter: dates.gouter
        case .soir:   dates.diner
        }
        guard let date, date < debutEnregistreur else { return nil }
        return date
    }

    static func moment(section: SectionRepas, profil: ProfilUtilisateur) -> MomentRatio {
        moment(section: section, modeRatio: profil.modeRatio)
    }

    nonisolated static func moment(section: SectionRepas, modeRatio: ModeRatio) -> MomentRatio {
        guard modeRatio == .parMoment else { return .unique }
        switch section {
        case .petitDejeuner: return .matin
        case .dejeuner:      return .midi
        case .enCas:         return .gouter
        case .diner, .nuit:  return .soir
        }
    }

    nonisolated static func parametre(_ moment: MomentRatio) -> ParametreSuivi {
        switch moment {
        case .unique: .ratioUnique
        case .matin:  .ratioPetitDejeuner
        case .midi:   .ratioDejeuner
        case .gouter: .ratioGouter
        case .soir:   .ratioDiner
        }
    }
}
