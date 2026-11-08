//
//  ConstatVerdictBasale.swift
//  diaviz
//

import Foundation

/// Ce que la carte « Verdict » de la tendance basale raconte : une phrase de
/// verdict, une phrase qui dit sur quoi il repose, et la frise des nuits qui
/// le composent. Source unique des textes — la carte de l'accueil reprend le
/// même verdict, pour que les deux ne puissent plus se contredire.
///
/// Vocabulaire des nuits aligné sur la frise C1 : concluante / dérive / hypo.
nonisolated struct ConstatVerdictBasale: Sendable, Equatable {

    enum EtatNuit: Sendable, Equatable {
        case concluante
        case deriveMontante
        case deriveDescendante
        case hypo
        /// Une des premières nuits à la nouvelle dose : ne compte pas encore.
        case observation
        /// Place encore à remplir avant un premier verdict — pas une nuit.
        case aVenir
    }

    struct Pastille: Sendable, Equatable, Identifiable {
        let id: Int
        /// Jour du soir de la nuit ; `nil` pour une place à venir.
        let date: Date?
        let etat: EtatNuit
        /// Ce que dit la phrase de verdict quand on touche la pastille.
        let titre: String
        /// Ce que dit la phrase d'explication quand on touche la pastille.
        let detail: String
        /// La nuit retenue précédente n'est pas la veille : un point gris
        /// marque le saut de dates.
        let sautAvant: Bool
        /// Statut imposé par l'utilisateur plutôt que calculé.
        var classeeParVous = false
    }

    let verdict: String
    let raison: String
    let pastilles: [Pastille]

    static let nuitsMinimales = 3
    static let nuitsObservation = ConfigBasale().nuitsObservationApresChangement

    init(analyse: AnalyseBasaleDetail, calendrier cal: Calendar = .current) {
        let verdictBasal = analyse.basalVerdict
        let retenues = analyse.nightChartData
            .filter(\.retenueDansVerdict)
            .sorted { $0.date < $1.date }
        // Tant qu'il n'y a pas de verdict, les nuits d'observation qui suivent
        // un changement de dose s'affichent aussi : elles disent où on en est.
        let observees = verdictBasal.state == .sufficient ? [] : analyse.nightChartData
            .filter { $0.enObservation && !$0.retenueDansVerdict }
        let affichees = (observees + retenues).sorted { $0.date < $1.date }

        var pastilles: [Pastille] = []
        var precedente: Date?
        for (i, nuit) in affichees.enumerated() {
            let saut = precedente.map {
                (cal.dateComponents([.day], from: cal.startOfDay(for: $0),
                                    to: cal.startOfDay(for: nuit.date)).day ?? 1) > 1
            } ?? false
            let etat = nuit.enObservation ? .observation : Self.etat(de: nuit)
            pastilles.append(Pastille(
                id: i, date: nuit.date, etat: etat,
                titre: "Nuit du \(Self.jour(nuit.date)) · \(Self.libelle(etat))",
                detail: Self.detail(de: nuit, etat: etat),
                sautAvant: saut,
                classeeParVous: nuit.classementManuel != nil
            ))
            precedente = nuit.date
        }

        if verdictBasal.state != .sufficient {
            let observationRestante = verdictBasal.doseChangedDate == nil ? 0
                : max(0, Self.nuitsObservation - observees.count)
            let manquant = observationRestante + max(0, Self.nuitsMinimales - retenues.count)
            for k in 0..<manquant {
                pastilles.append(Pastille(
                    id: affichees.count + k, date: nil, etat: .aVenir,
                    titre: "Nuit à venir",
                    detail: "Encore \(Self.nuits(manquant)) avant un verdict.",
                    sautAvant: false
                ))
            }
        }
        self.pastilles = pastilles

        let (v, r) = Self.phrases(analyse: analyse, verdictBasal: verdictBasal,
                                  retenues: retenues, pastilles: pastilles)
        self.verdict = v
        self.raison = r
    }

    // MARK: - Verdict et explication

    private static func phrases(
        analyse: AnalyseBasaleDetail,
        verdictBasal: BasalVerdict,
        retenues: [NightChartData],
        pastilles: [Pastille]
    ) -> (String, String) {
        let n = retenues.count

        switch verdictBasal.state {
        case .noData, .recentChange:
            if let changement = verdictBasal.doseChangedDate {
                return ("Nouvelle dose en observation", phraseChangementDose(analyse, depuis: changement))
            }
            if n == 0 { return ("Pas encore de verdict", "Aucune nuit exploitable pour l'instant.") }
            return ("Pas encore de verdict",
                    "\(nuits(n)) exploitable\(n > 1 ? "s" : "") sur les \(nuitsMinimales) nécessaires.")
        case .sufficient:
            break
        }

        let nuitsHypo = zip(retenues, pastilles).filter { $0.1.etat == .hypo }.map(\.0)
        let compte: (EtatNuit) -> Int = { e in pastilles.filter { $0.etat == e }.count }

        if analyse.enAmelioration {
            return ("En amélioration", "Vos dernières nuits ne montrent plus de tendance nette.")
        }

        switch analyse.verdict {
        case .tropHaute:
            let verdict = "Tendance basse observée"
            if nuitsHypo.count == 1, let nuit = nuitsHypo.first, nuit.classementManuel == .hypo {
                return (verdict, "Une hypo la nuit du \(jour(nuit.date)), classée par vous, suffit à ce verdict.")
            }
            if nuitsHypo.count == 1, let nuit = nuitsHypo.first, let h = nuit.hypoRetenue {
                let autres = n - 1
                let suite = autres > 0 ? " Vos \(autres) autre\(autres > 1 ? "s" : "") nuit\(autres > 1 ? "s" : "") n'en montre\(autres > 1 ? "nt" : "") pas." : ""
                return (verdict, "Une hypo de \(h.dureeMin) min la nuit du \(jour(nuit.date)) suffit à ce verdict.\(suite)")
            }
            if nuitsHypo.count > 1 {
                return (verdict, "Des hypos sur \(nuitsHypo.count) de vos \(n) dernières nuits.")
            }
            if let rechute = retenues.last(where: { $0.bilanHypos.rechutes > 0 }) {
                return (verdict, "Une hypo avec rechute après resucrage la nuit du \(jour(rechute.date)) suffit à ce verdict.")
            }
            return (verdict, "\(compte(.deriveDescendante)) de vos \(n) dernières nuits sont en dérive descendante.")
        case .tropBasse:
            return ("Tendance haute observée",
                    "\(compte(.deriveMontante)) de vos \(n) dernières nuits sont en dérive montante.")
        case .adaptee:
            let c = compte(.concluante)
            if c == n { return ("Stable", "Vos \(n) dernières nuits sont concluantes, sans hypo.") }
            return ("Stable", "\(c) de vos \(n) dernières nuits sont concluantes, aucune hypo.")
        case .donneesInsuffisantes:
            return ("Pas encore de verdict",
                    "\(nuits(n)) exploitable\(n > 1 ? "s" : "") sur les \(nuitsMinimales) nécessaires.")
        }
    }

    private static func phraseChangementDose(_ analyse: AnalyseBasaleDetail, depuis date: Date) -> String {
        let historique = analyse.doseHistory
        let actuelle = historique.first(where: \.isCurrent)?.dose ?? analyse.doseActuelle
        let precedente = historique.filter { !$0.isCurrent }.max(by: { $0.startDate < $1.startDate })?.dose
        let changement = precedente.map { "Lente passée de \(dose($0)) à \(dose(actuelle)) u le \(jour(date))." }
            ?? "Lente à \(dose(actuelle)) u depuis le \(jour(date))."
        return "\(changement) Les \(nuitsObservation) premières nuits sont en observation, puis \(nuitsMinimales) nuits exploitables donnent un verdict."
    }

    // MARK: - Une nuit

    private static func etat(de nuit: NightChartData) -> EtatNuit {
        switch nuit.classementManuel {
        case .concluante:        return .concluante
        case .deriveMontante:    return .deriveMontante
        case .deriveDescendante: return .deriveDescendante
        case .hypo:              return .hypo
        case .ecartee, nil:      break
        }
        if nuit.hypoRetenue != nil { return .hypo }
        switch nuit.categorieVerdict {
        case .tendanceHaute: return .deriveMontante
        case .tendanceBasse: return nuit.bilanHypos.rechutes > 0 ? .hypo : .deriveDescendante
        case .stable, nil:   return .concluante
        }
    }

    private static func libelle(_ etat: EtatNuit) -> String {
        switch etat {
        case .concluante:                         return "concluante"
        case .deriveMontante, .deriveDescendante: return "dérive"
        case .hypo:                               return "hypo"
        case .observation:                        return "observation"
        case .aVenir:                             return "à venir"
        }
    }

    private static func detail(de nuit: NightChartData, etat: EtatNuit) -> String {
        if nuit.classementManuel != nil {
            return "Classée par vous. Calcul de l'app : \(nuit.libelleCalcul)."
        }
        if etat == .observation {
            return "Ne compte pas encore : le temps que la nouvelle dose s'installe."
        }
        if etat == .hypo {
            guard let h = nuit.hypoRetenue else { return "Hypo avec rechute après resucrage." }
            let suite = h.resucree ? "resucrée" : "remontée sans resucrage"
            return "Hypo de \(h.dureeMin) min à \(heure(h.heure)), \(suite)."
        }
        if let pente = nuit.slopeZone3,
           let z3 = nuit.zones.first(where: { $0.zone == .nuitProfonde }) {
            let heures = z3.timeRange.upperBound.timeIntervalSince(z3.timeRange.lowerBound) / 3600
            let derive = Int((pente * heures).rounded())
            return "\(String(format: "%+d", derive)) mg/dL entre \(heure(z3.timeRange.lowerBound)) et \(heure(z3.timeRange.upperBound))."
        }
        if let pic = nuit.hyperRetenue {
            return "Hyper à \(heure(pic)), sans repas ni rebond pour l'expliquer."
        }
        return "Dérive non mesurable cette nuit-là."
    }

    // MARK: - Formats

    /// « 19 oct. »
    static func jour(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }

    private static func heure(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02dh%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func dose(_ d: Double) -> String {
        d == d.rounded() ? String(format: "%.0f", d) : String(format: "%.1f", d)
    }

    private static func nuits(_ n: Int) -> String { n > 1 ? "\(n) nuits" : "\(n) nuit" }
}
