//
//  CalculHyposCoucher.swift
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
    /// Instant de l'événement — **sémantique différente selon la branche** :
    /// jour calendaire à minuit côté B2, heure exacte de la correction côté
    /// B3. Ne jamais s'en servir pour retrouver la nuit : utiliser `dateNuit`.
    let date: Date
    /// Jour métabolique (06h→06h) de la nuit à laquelle ce soir appartient,
    /// normalisé à minuit — même clé que `NightChartData.date`. Champ dédié
    /// parce que `date` mélangeait deux conventions : le rapprochement avec
    /// B1 renvoyait la nuit de la veille pour tout soir B2.
    let dateNuit: Date
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
    /// Glucides (g) du resucrage préventif qui a évité l'hypo. `nil` hors de
    /// ce cas — c'est la seule prise dont l'app peut dire qu'elle a « tenu ».
    var glucidesHypoEvitee: Int? = nil
    /// `true` si un resucrage correctif de ce soir a été suivi d'une nouvelle
    /// hypo dans l'heure (cf. `DetectionRechute`).
    var rechute: Bool = false
    /// Minutes entre l'événement et l'hypo — `nil` si stable ou inconnu.
    let delaiHypoMinutes: Int?
    /// Issue B3 détaillée (`nil` pour un soir sans correction). L'insuffisant
    /// est conservé pour la sheet détail mais n'entre pas dans le focus hypo.
    let issueCorrection: IssueCorrection?
}

// MARK: - Snapshot de la page

/// Snapshot prêt à afficher de la page « Hypos au coucher » (fusion B2 + B3,
/// focus hypo). Dérivé des analyses B2/B3 réelles + timeline B1.
///
/// Ne porte que des **faits comptables** : chaque métrique exposée ici se
/// recompte à la main depuis `soirs`. Aucun modèle, aucune inférence.
nonisolated struct AnalyseHyposCoucher: Sendable, Equatable {
    /// Tous les soirs analysés, triés par date décroissante.
    let soirs: [SoirCoucher]
    let doseActuelle: Double
    let changementDoseRecent: Date?
    let seuilCoucher: Int

    var totalSoirs: Int { soirs.count }
    var soirsEnHypo: [SoirCoucher] { soirs.filter(\.enHypo) }
    var totalHypos: Int { soirsEnHypo.count }

    /// Hypos où un resucrage correctif n'a pas tenu (nouvelle hypo dans
    /// l'heure). Sous-ensemble strict de `soirsEnHypo` — jamais additionné
    /// au total, c'est un dont, pas un en plus.
    var soirsAvecRechute: [SoirCoucher] { soirsEnHypo.filter(\.rechute) }
    var totalRechutes: Int { soirsAvecRechute.count }

    /// Soirs où un resucrage préventif a précédé une hypo qui n'a pas eu lieu.
    /// **Hors** du compteur d'hypos (ce n'en est pas une), mais comptés à part :
    /// sans ça, ils se confondaient avec les soirs où rien ne s'est passé.
    var soirsHypoEvitee: [SoirCoucher] { soirs.filter(\.hypoEvitee) }
    var totalHyposEvitees: Int { soirsHypoEvitee.count }

    /// Glucides **médians** des resucrages préventifs qui ont tenu. Médiane et
    /// non moyenne : sur 1 à 3 prises, une valeur extrême emporterait la
    /// moyenne et donnerait un chiffre que l'utilisateur n'a jamais pris.
    /// `nil` si aucun préventif n'a évité d'hypo.
    var glucidesTypiquesHypoEvitee: Int? {
        let valeurs = soirsHypoEvitee.compactMap(\.glucidesHypoEvitee).sorted()
        guard !valeurs.isEmpty else { return nil }
        return valeurs[valeurs.count / 2]
    }
}

// MARK: - Calculateur

/// Assembleur de la page **« Hypos au coucher »** : fusionne les populations
/// B2 (couchers sous seuil sans correction) et B3 (soirs avec correction) en
/// soirs unifiés, prêts à être comptés et listés.
///
/// Focus **hypo** uniquement (l'événement dangereux) : l'issue « insuffisant »
/// de B3 est conservée sur le soir pour la sheet détail, mais n'alimente aucun
/// compteur.
///
/// Ne mine **aucun pattern** : la section « Situations observées » (croisements
/// de facteurs minés par énumération) a été retirée en août 2026 — un facteur
/// isolé, sans mise en regard des autres analyses, ne disait rien d'actionnable
/// et alourdissait la page. La valeur est dans les faits comptés et la liste
/// des soirs, pas dans une corrélation à 4 nuits.
nonisolated enum CalculHyposCoucher {

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

        /// Jour métabolique (06h→06h) d'un instant, normalisé à minuit — même
        /// clé que `NightChartData.date`. Une correction à 00h30 appartient
        /// ainsi à la nuit de la veille, pas à celle qui commence.
        func jourNuit(_ instant: Date) -> Date {
            cal.startOfDay(for: ScoreService.debutJourMetabolique(pour: instant))
        }

        let soirsB2 = endormissement.nuits.map { nuit in
            SoirCoucher(
                id: nuit.id, date: nuit.date, dateNuit: cal.startOfDay(for: nuit.date),
                glycemie: nuit.glycemieCoucher, tendance: nuit.tendance,
                correction: nil, glucides: nuit.glucides, sport: nuit.sport,
                iob: nuit.iob, charge: nuit.charge,
                categorieB1: categorieB1(nuit.date),
                enHypo: nuit.issue.estHypo,
                hypoEvitee: nuit.issue.estHypoEvitee,
                glucidesHypoEvitee: {
                    if case let .hypoEvitee(g) = nuit.issue { return g }
                    return nil
                }(),
                rechute: nuit.rechute,
                delaiHypoMinutes: { if case let .hypo(d) = nuit.issue { return d }; return nil }(),
                issueCorrection: nil
            )
        }

        let soirsB3 = corrections.corrections.map { corr in
            SoirCoucher(
                id: corr.id, date: corr.date, dateNuit: jourNuit(corr.date),
                glycemie: corr.glycemie, tendance: corr.tendance,
                correction: corr.dose, glucides: corr.glucides, sport: corr.sport,
                iob: corr.iob, charge: corr.charge,
                categorieB1: categorieB1(corr.date),
                enHypo: corr.issue == .surCorrection,
                rechute: corr.rechute,
                delaiHypoMinutes: nil,
                issueCorrection: corr.issue
            )
        }

        return soirsB2 + soirsB3
    }
}

#if DEBUG
extension AnalyseHyposCoucher {
    /// Fusion des mocks B2/B3 existants — pour previews.
    static var mock: AnalyseHyposCoucher {
        CalculHyposCoucher.analyser(
            endormissement: .mock, corrections: .mock, timeline: []
        )
    }

    /// Variante avec une timeline B1 synthétique et un changement de dose —
    /// exerce l'en-tête « depuis le changement de dose » et la catégorie B1
    /// affichée dans la sheet détail.
    static var mockRiche: AnalyseHyposCoucher {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let cal = Calendar.current
        let timeline: [NuitTimeline] = (0..<13).map { i in
            let date = base.addingTimeInterval(Double(i) * 86_400)
            let categorie: CategorieNuit = [1, 2, 3, 5, 7].contains(i) ? .tendanceBasse : .stable
            return NuitTimeline(date: cal.startOfDay(for: date), etat: .valide(categorie: categorie), avantChangementDose: false)
        }
        return CalculHyposCoucher.analyser(
            endormissement: .mock, corrections: .mock, timeline: timeline,
            changementDoseRecent: base.addingTimeInterval(-13 * 86_400)
        )
    }
}
#endif
