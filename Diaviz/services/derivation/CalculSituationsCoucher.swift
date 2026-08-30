//
//  CalculSituationsCoucher.swift
//  diaviz
//

import Foundation

// MARK: - Soir unifié (fusion B2 + B3)

/// Un soir analysé par la page « Hypos au coucher » — union des deux
/// populations existantes : couchers sous le seuil **sans** correction (B2)
/// et soirs **avec** correction rapide au coucher (B3). Les couchers hauts
/// sans correction restent hors analyse (zone de confort, cadrage B2).
nonisolated struct SoirCoucher: Identifiable, Sendable, Equatable {
    let id: UUID
    let date: Date
    /// Glycémie (mg/dL) au moment de l'événement (lente pour B2, correction pour B3).
    let glycemie: Int
    let tendance: TendanceGlycemie
    /// Dose de la correction rapide (u) — `nil` si soir sans correction (B2).
    let correction: Double?
    let glucides: Double?
    let sport: SportResume?
    /// IOB résiduel **avant** l'événement (correction exclue du calcul côté B3).
    let iob: Double?
    let charge: ChargeActivite
    /// Catégorie B1 de la même nuit (dérive zone 3) — `nil` si nuit non
    /// classée par B1 (exclue / sans données).
    let categorieB1: CategorieNuit?
    /// `true` si le soir a fini en hypo (issue B2, ou sur-correction B3).
    let enHypo: Bool
    /// `true` si un resucrage **préventif** a été pris au coucher sans que la
    /// glycémie ne descende sous le seuil — hypo évitée. Ni hypo ni stable :
    /// hors du compteur d'hypos, mais compté et affiché à part.
    var hypoEvitee: Bool = false
    /// Minutes entre l'événement et l'hypo — `nil` si stable ou inconnu.
    let delaiHypoMinutes: Int?
    /// Issue B3 détaillée (`nil` pour un soir sans correction). L'insuffisant
    /// est conservé pour la sheet détail mais n'entre pas dans le focus hypo.
    let issueCorrection: IssueCorrection?
}

// MARK: - Facteurs de contexte

/// Tranche de glycémie au coucher — l'axe « levier » principal. La dernière
/// tranche n'existe que corrigée (un coucher ≥ 160 sans correction est hors
/// population).
nonisolated enum TrancheCoucher: String, Sendable, CaseIterable {
    case moins100
    case de100a130
    case de130a160
    case hautCorrige

    var libelle: String {
        switch self {
        case .moins100:    return "coucher < 100"
        case .de100a130:   return "coucher 100-130"
        case .de130a160:   return "coucher 130-160"
        case .hautCorrige: return "coucher ≥ 160 corrigé"
        }
    }

    nonisolated static func pour(glycemie: Int) -> TrancheCoucher {
        if glycemie >= 160 { return .hautCorrige }
        if glycemie >= 130 { return .de130a160 }
        if glycemie >= 100 { return .de100a130 }
        return .moins100
    }
}

/// Facteur de contexte binaire ou par tranche, évaluable sur chaque soir.
/// La `famille` empêche de croiser deux facteurs redondants (ex. « insuline
/// active » et « correction prise » se recouvrent presque toujours).
nonisolated enum FacteurCoucher: Hashable, Sendable {
    case tranche(TrancheCoucher)
    case sportJour
    case insulineActive
    case chargeIntense
    case nuitDescendante
    case correctionPrise

    /// Famille logique — deux facteurs de la même famille ne se croisent pas.
    var famille: String {
        switch self {
        case .tranche:          return "glycemie"
        case .sportJour:        return "sport"
        case .insulineActive, .correctionPrise: return "insuline"
        case .chargeIntense:    return "charge"
        case .nuitDescendante:  return "basale"
        }
    }

    /// Libellé factuel court.
    var libelle: String {
        switch self {
        case .tranche(let t):   return t.libelle
        case .sportJour:        return "sport le jour même"
        case .insulineActive:   return "insuline encore active"
        case .chargeIntense:    return "semaine intense"
        case .nuitDescendante:  return "nuit « descendante » (B1)"
        case .correctionPrise:  return "correction prise"
        }
    }

    /// SF Symbol associé, affiché en tête du libellé.
    var icone: String {
        switch self {
        case .tranche:          return "drop.fill"
        case .sportJour:        return "figure.run"
        case .insulineActive:   return "bolt.fill"
        case .chargeIntense:    return "flame.fill"
        case .nuitDescendante:  return "chart.line.downtrend.xyaxis"
        case .correctionPrise:  return "syringe.fill"
        }
    }

    /// Libellé du complément (« même coucher, sans X ») — la ligne de contraste.
    var libelleAbsence: String {
        switch self {
        case .tranche:          return "autres couchers"
        case .sportJour:        return "jour sans sport"
        case .insulineActive:   return "sans insuline active"
        case .chargeIntense:    return "semaine calme"
        case .nuitDescendante:  return "nuit stable"
        case .correctionPrise:  return "sans correction"
        }
    }

    nonisolated func present(dans soir: SoirCoucher) -> Bool {
        switch self {
        case .tranche(let t):
            return TrancheCoucher.pour(glycemie: soir.glycemie) == t
        case .sportJour:        return soir.sport != nil
        case .insulineActive:   return soir.iob != nil
        case .chargeIntense:    return soir.charge == .intense
        case .nuitDescendante:  return soir.categorieB1 == .tendanceBasse
        case .correctionPrise:  return soir.correction != nil
        }
    }
}

// MARK: - Situation minée

/// Une combinaison de facteurs (1 ou 2) dont le taux d'hypo se démarque
/// nettement de son complément. Toujours affichée avec ses **dénominateurs**
/// et sa ligne de contraste — co-occurrence observée, jamais cause affirmée.
nonisolated struct SituationCoucher: Identifiable, Sendable, Equatable {
    var id: String { facteurs.map(\.libelle).joined(separator: "·") }

    /// 1 facteur (« facteur seul ») ou 2 (levier × terrain).
    let facteurs: [FacteurCoucher]
    /// Soirs correspondant à la situation (tappables → détail).
    let soirs: [SoirCoucher]
    let hypos: Int
    /// Complément : pour une paire, mêmes soirs sur le 1er facteur **sans** le
    /// 2nd (contraste « même coucher, semaine calme ») ; pour un facteur seul,
    /// tous les autres soirs.
    let complementTotal: Int
    let complementHypos: Int

    var total: Int { soirs.count }
    /// Effectif trop faible pour être robuste — affiché avec ⚠︎.
    var fragile: Bool { total < 4 }
    /// Écart de taux d'hypo situation vs complément (0…1) — clé de tri.
    var ecart: Double {
        let taux = Double(hypos) / Double(max(1, total))
        let tauxComp = Double(complementHypos) / Double(max(1, complementTotal))
        return taux - tauxComp
    }

    var titre: String { facteurs.map(\.libelle).joined(separator: " · ") }
    var estFacteurSeul: Bool { facteurs.count == 1 }
    /// Libellé de la ligne de contraste.
    var libelleComplement: String {
        guard let dernier = facteurs.last else { return "autres soirs" }
        if facteurs.count == 2 {
            return "même situation, \(dernier.libelleAbsence)"
        }
        return dernier.libelleAbsence
    }
}

// MARK: - Snapshot de la page

/// Snapshot prêt à afficher de la page « Hypos au coucher » (fusion B2 + B3,
/// focus hypo). Dérivé des analyses B2/B3 réelles + timeline B1.
nonisolated struct AnalyseHyposCoucher: Sendable, Equatable {
    /// Tous les soirs analysés, triés par date décroissante.
    let soirs: [SoirCoucher]
    let situations: [SituationCoucher]
    let doseActuelle: Double
    let changementDoseRecent: Date?
    let seuilCoucher: Int

    var totalSoirs: Int { soirs.count }
    var soirsEnHypo: [SoirCoucher] { soirs.filter(\.enHypo) }
    var totalHypos: Int { soirsEnHypo.count }
    /// Soirs où un resucrage préventif a précédé une hypo qui n'a pas eu lieu.
    /// **Hors** du compteur d'hypos (ce n'en est pas une), mais affichés à part :
    /// sans ça, ils se confondaient avec les soirs où rien ne s'est passé.
    var soirsHypoEvitee: [SoirCoucher] { soirs.filter(\.hypoEvitee) }
    var totalHyposEvitees: Int { soirsHypoEvitee.count }
}

// MARK: - Calculateur

/// Assembleur de la page **« Hypos au coucher »** : fusionne les populations
/// B2 (couchers sous seuil sans correction) et B3 (soirs avec correction) en
/// soirs unifiés, puis **mine les situations** — énumération exhaustive des
/// combinaisons de facteurs (1 et 2), retenues si l'effectif et l'écart de
/// taux d'hypo vs complément sont suffisants. Pas de modèle : chaque chiffre
/// est recomptable à la main depuis les soirs listés.
///
/// Focus **hypo** uniquement (l'événement dangereux) : l'issue « insuffisant »
/// de B3 est conservée sur le soir mais n'alimente ni le compteur ni le mining.
nonisolated enum CalculSituationsCoucher {

    /// Effectif minimal d'une situation pour être affichée.
    static let effectifMinimal = 3
    /// Hypos minimales dans la situation (évite le « 1/3 » anecdotique).
    static let hyposMinimales = 2
    /// Écart minimal de taux d'hypo situation vs complément (points de taux).
    static let ecartMinimal = 0.25

    // MARK: Point d'entrée

    static func analyser(
        endormissement: AnalyseEndormissement,
        corrections: AnalyseCorrections,
        timeline: [NuitTimeline],
        changementDoseRecent: Date? = nil
    ) -> AnalyseHyposCoucher {
        let soirs = fusionner(
            endormissement: endormissement, corrections: corrections, timeline: timeline
        )
        return AnalyseHyposCoucher(
            soirs: soirs.sorted { $0.date > $1.date },
            situations: minerSituations(soirs),
            doseActuelle: endormissement.doseActuelle,
            changementDoseRecent: changementDoseRecent,
            seuilCoucher: endormissement.seuilCoucher
        )
    }

    // MARK: Fusion B2 + B3 → soirs unifiés

    private static func fusionner(
        endormissement: AnalyseEndormissement,
        corrections: AnalyseCorrections,
        timeline: [NuitTimeline]
    ) -> [SoirCoucher] {
        let cal = Calendar.current

        func categorieB1(_ date: Date) -> CategorieNuit? {
            let jour = cal.startOfDay(for: date)
            guard let nuit = timeline.first(where: { cal.startOfDay(for: $0.date) == jour }) else { return nil }
            if case let .valide(categorie) = nuit.etat { return categorie }
            return nil
        }

        let soirsB2 = endormissement.nuits.map { nuit in
            SoirCoucher(
                id: nuit.id, date: nuit.date,
                glycemie: nuit.glycemieCoucher, tendance: nuit.tendance,
                correction: nil, glucides: nuit.glucides, sport: nuit.sport,
                iob: nuit.iob, charge: nuit.charge,
                categorieB1: categorieB1(nuit.date),
                enHypo: nuit.issue.estHypo,
                hypoEvitee: nuit.issue.estHypoEvitee,
                delaiHypoMinutes: { if case let .hypo(d) = nuit.issue { return d }; return nil }(),
                issueCorrection: nil
            )
        }

        let soirsB3 = corrections.corrections.map { corr in
            SoirCoucher(
                id: corr.id, date: corr.date,
                glycemie: corr.glycemie, tendance: corr.tendance,
                correction: corr.dose, glucides: corr.glucides, sport: corr.sport,
                iob: corr.iob, charge: corr.charge,
                categorieB1: categorieB1(corr.date),
                enHypo: corr.issue == .surCorrection,
                delaiHypoMinutes: nil,
                issueCorrection: corr.issue
            )
        }

        return soirsB2 + soirsB3
    }

    // MARK: Mining des situations

    /// Énumération exhaustive : facteurs seuls + paires de familles
    /// différentes. Volume trivial (≈ 10 facteurs → ≈ 50 combinaisons),
    /// chaque situation gardée si effectif, hypos et écart suffisent.
    /// Triées par écart décroissant.
    static func minerSituations(_ soirs: [SoirCoucher]) -> [SituationCoucher] {
        guard !soirs.isEmpty else { return [] }

        var facteurs: [FacteurCoucher] = TrancheCoucher.allCases.map { .tranche($0) }
        facteurs += [.sportJour, .insulineActive, .chargeIntense, .nuitDescendante, .correctionPrise]

        var candidates: [SituationCoucher] = []

        // Facteurs seuls — complément = tous les autres soirs.
        for f in facteurs {
            let dedans = soirs.filter { f.present(dans: $0) }
            let dehors = soirs.filter { !f.present(dans: $0) }
            if let s = construire([f], soirs: dedans, complement: dehors) {
                candidates.append(s)
            }
        }

        // Paires (familles différentes) — complément **ancré sur le 1er
        // facteur** : mêmes soirs côté levier, sans le facteur terrain
        // (c'est le contraste qui rend le fait lisible).
        for (i, a) in facteurs.enumerated() {
            for b in facteurs.dropFirst(i + 1) where a.famille != b.famille {
                let base = soirs.filter { a.present(dans: $0) }
                let dedans = base.filter { b.present(dans: $0) }
                let dehors = base.filter { !b.present(dans: $0) }
                if let s = construire([a, b], soirs: dedans, complement: dehors) {
                    candidates.append(s)
                }
            }
        }

        // Une paire n'apporte rien si son écart n'améliore pas nettement le
        // meilleur de ses facteurs seuls (évite les doublons visuels).
        let seuls = candidates.filter(\.estFacteurSeul)
        let paires = candidates.filter { !$0.estFacteurSeul }.filter { paire in
            let meilleursSeuls = seuls
                .filter { paire.facteurs.contains($0.facteurs[0]) }
                .map(\.ecart).max() ?? 0
            return paire.ecart > meilleursSeuls + 0.05
        }

        return (seuls + paires).sorted { $0.ecart > $1.ecart }
    }

    private static func construire(
        _ facteurs: [FacteurCoucher],
        soirs: [SoirCoucher],
        complement: [SoirCoucher]
    ) -> SituationCoucher? {
        let hypos = soirs.filter(\.enHypo).count
        guard soirs.count >= effectifMinimal,
              hypos >= hyposMinimales,
              !complement.isEmpty else { return nil }

        let situation = SituationCoucher(
            facteurs: facteurs,
            soirs: soirs.sorted { $0.date > $1.date },
            hypos: hypos,
            complementTotal: complement.count,
            complementHypos: complement.filter(\.enHypo).count
        )
        guard situation.ecart >= ecartMinimal else { return nil }
        return situation
    }
}

#if DEBUG
extension AnalyseHyposCoucher {
    /// Fusion des mocks B2/B3 existants — pour previews. Timeline vide : le
    /// facteur « nuit descendante (B1) » ne peut jamais matcher, donc aucune
    /// situation ne le porte. Utiliser `.mockRiche` pour l'exercer.
    static var mock: AnalyseHyposCoucher {
        CalculSituationsCoucher.analyser(
            endormissement: .mock, corrections: .mock, timeline: []
        )
    }

    /// Variante enrichie d'une timeline B1 synthétique, pour que le facteur
    /// « nuit descendante (B1) » produise de vraies situations en preview —
    /// sinon il reste invisible avec `.mock` (timeline vide).
    static var mockRiche: AnalyseHyposCoucher {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let cal = Calendar.current
        // Descendante sur un mélange de nuits hypo et stables (0..8), stable
        // ensuite — donne un contraste réel, pas une corrélation forcée à 100%.
        let timeline: [NuitTimeline] = (0..<13).map { i in
            let date = base.addingTimeInterval(Double(i) * 86_400)
            let categorie: CategorieNuit = [1, 2, 3, 5, 7].contains(i) ? .tendanceBasse : .stable
            return NuitTimeline(date: cal.startOfDay(for: date), etat: .valide(categorie: categorie), avantChangementDose: false)
        }
        return CalculSituationsCoucher.analyser(
            endormissement: .mock, corrections: .mock, timeline: timeline,
            changementDoseRecent: base.addingTimeInterval(-13 * 86_400)
        )
    }
}
#endif
