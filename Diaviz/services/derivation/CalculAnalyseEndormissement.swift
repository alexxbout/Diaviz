//
//  CalculAnalyseEndormissement.swift
//  diaviz
//

import Foundation

// MARK: - Entrées (value types, découplés de SwiftData)

/// Ancrage minimal d'une nuit pour B2/B3, dérivé de `NightChartData` (B1).
/// Volontairement réduit aux champs stables et publics de B1 — B2/B3 ne
/// dépendent pas de la structure interne de ses zones/events.
nonisolated struct AncrageNuit: Sendable {
    let dateNuit: Date
    /// Heure de la lente du soir. `doseLente == 0` signale qu'aucune lente
    /// n'a été trouvée cette nuit-là (sentinelle héritée de B1) — la nuit est
    /// alors ignorée par B2/B3 (rien à ancrer).
    let basaleTime: Date
    let doseLente: Double
    /// Glycémie au moment de la lente (`NightChartData.startGlucose`).
    let glycemieCoucher: Int
}

/// Faits bruts nécessaires à l'analyse B2, mappés en value types par le
/// service hub pour que le calculateur reste **pur**.
nonisolated struct EntreesEndormissement: Sendable {
    /// Nuits ancrées (fenêtre B1 : 14 nuits), plus récente ou ancienne peu importe.
    let nuits: [AncrageNuit]
    /// Mesures CGM brutes `(date, valeur, tendance)` — indépendantes de la
    /// grille rééchantillonnée de B1 (celle-ci ne couvre que 21h→07h, trop
    /// étroite si la lente est prise tôt).
    let lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)]
    let rapides: [(heure: Date, dose: Double, correction: Bool)]
    /// Repas **hors resucrages** (les repas badgés basculent ci-dessous).
    let repas: [(heure: Date, glucides: Int)]
    /// Resucrages `(heure, glucides, intention)` — modèle `Resucrage` du hub
    /// + repas entièrement badgés. L'intention distingue une hypo traitée
    /// (`correctifHypo`) d'une hypo **évitée** (préventifs).
    let resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)]
    /// Séances de sport `(début, résumé)` — résumé déjà mappé (type/intensité
    /// en libellés français) par le service hub.
    let sports: [(debut: Date, resume: SportResume)]
    let pauses: [(debut: Date, fin: Date?)]
}

nonisolated struct ConfigEndormissement: Sendable {
    /// Seuil de coucher analysé (mg/dL) — couchers au-dessus exclus.
    /// Provisoirement constant (cadrage B2 : « deviendra un réglage
    /// utilisateur »).
    var seuilCoucher: Int = 160
    var seuilHypo: Int = 70
    var diaHeures: Double = 4
    var picMinutes: Double = 75
}

/// Assembleur **B2 — endormissement (hypos au coucher)** : dérivation pure,
/// jamais persistée. Reprend l'ancrage de nuit calculé par B1 (lente, zones
/// 1-2), remonte les hypos survenues ~2h post-lente pour les couchers sous
/// `seuilCoucher`, avec leur contexte (IOB, sport, charge d'activité).
///
/// Frontière avec B3 : une nuit portant une **correction rapide** dans la
/// fenêtre de coucher (zones 1+2, soit lente −3h → lente +2h) est **exclue**
/// d'ici — c'est un événement B3, pas B2 (cadrage : « couché sous le seuil
/// sans correction → B2 ; correction présente → B3 »).
///
/// Doc : Eraser « Diaviz / B2 — Endormissement (hypos au coucher) ».
///
/// `nonisolated` sur le type : le projet a `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, donc sans ce marquage les membres seraient implicitement
/// MainActor-isolés, inutilisables depuis un calculateur pur.
nonisolated enum CalculAnalyseEndormissement {

    // MARK: - Point d'entrée

    static func analyser(
        entrees: EntreesEndormissement,
        doseActuelle: Double,
        changementDoseRecent: Date?,
        config: ConfigEndormissement = ConfigEndormissement()
    ) -> AnalyseEndormissement {
        let cal = Calendar.current
        let nuitsRetenues = entrees.nuits
            .filter { $0.doseLente > 0 }
            .filter { avantChangement($0.dateNuit, changement: changementDoseRecent, cal: cal) == false }

        let nuits: [NuitEndormissement] = nuitsRetenues.compactMap { nuit in
            construireNuit(nuit, entrees: entrees, config: config, cal: cal)
        }
        .sorted { $0.glycemieCoucher < $1.glycemieCoucher }

        return AnalyseEndormissement(seuilCoucher: config.seuilCoucher, doseActuelle: doseActuelle, nuits: nuits)
    }

    /// `true` si `date` est strictement antérieure au dernier changement de
    /// dose de lente — même convention que B1 (fenêtre comparable).
    private static func avantChangement(_ date: Date, changement: Date?, cal: Calendar) -> Bool {
        guard let changement else { return false }
        return cal.startOfDay(for: date) < cal.startOfDay(for: changement)
    }

    // MARK: - Construction d'une nuit

    private static func construireNuit(
        _ nuit: AncrageNuit,
        entrees: EntreesEndormissement,
        config: ConfigEndormissement,
        cal: Calendar
    ) -> NuitEndormissement? {
        let L = nuit.basaleTime
        let z1 = L.addingTimeInterval(-3 * 3600)...L
        let z2 = L...L.addingTimeInterval(2 * 3600)

        // Mode pause actif sur la fenêtre de coucher → exclue (donnée
        // enregistrée mais hors analyse, principe CLAUDE.md).
        let enPause = entrees.pauses.contains { p in
            let fin = p.fin ?? z2.upperBound
            return fin >= z1.lowerBound && p.debut <= z2.upperBound
        }
        guard !enPause else { return nil }

        // Frontière B3 : correction rapide dans la fenêtre de coucher →
        // cette occasion est matière à B3, pas à B2.
        let correctionPresente = entrees.rapides.contains {
            $0.correction && (z1.contains($0.heure) || z2.contains($0.heure))
        }
        guard !correctionPresente else { return nil }

        // Population B2 : couchers sous le seuil configuré uniquement.
        guard nuit.glycemieCoucher < config.seuilCoucher else { return nil }

        // Resucrages de la fenêtre de coucher — pèsent sur l'issue.
        let resucragesCoucher = entrees.resucrages.filter {
            z1.contains($0.heure) || z2.contains($0.heure)
        }
        let pointsZ2 = entrees.lectures.filter { z2.contains($0.date) }
        let issue = issueEndormissement(
            pointsZ2, basaleTime: L, seuilHypo: config.seuilHypo,
            resucrages: resucragesCoucher
        )

        let tendance = tendanceProche(entrees.lectures, a: L) ?? .stable
        let glucides = glucidesAutourDuCoucher(
            entrees.repas, resucrages: entrees.resucrages, z1: z1, z2: z2
        )
        let sport = sportDuJour(entrees.sports, jour: nuit.dateNuit, cal: cal)
        let charge = CalculChargeActivite.charge(
            jusqua: nuit.dateNuit,
            activites: entrees.sports.map { (debut: $0.debut, dureeMin: 0) }
        )
        let iob = iobAuCoucher(entrees.rapides, a: L, config: config)

        return NuitEndormissement(
            id: UUID(),
            date: nuit.dateNuit,
            glycemieCoucher: nuit.glycemieCoucher,
            tendance: tendance,
            glucides: glucides,
            sport: sport,
            iob: iob,
            charge: charge,
            issue: issue
        )
    }

    // MARK: - Issue (hypo zone 2 vs stable)

    /// Issue de la zone d'endormissement (~2h post-lente), par ordre de
    /// priorité : creux CGM → hypo ; resucrage **correctif** loggé sans creux
    /// visible → hypo quand même (l'utilisateur a confirmé l'hypo, le capteur
    /// l'a manquée — retard CGM ou correction très rapide) ; resucrage
    /// **préventif** sans creux → hypo évitée ; sinon stable.
    ///
    /// Sans le cas « évitée », un préventif qui fonctionne rendait le soir
    /// indistinguable d'un soir où rien ne s'est passé — le plus instructif
    /// des deux disparaissait dans « stable ».
    private static func issueEndormissement(
        _ points: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)],
        basaleTime: Date,
        seuilHypo: Int,
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)]
    ) -> IssueEndormissement {
        if let premierBas = points.first(where: { $0.valeur < seuilHypo }) {
            let delai = Int(premierBas.date.timeIntervalSince(basaleTime) / 60)
            return .hypo(delaiMinutes: max(0, delai))
        }
        if let correctif = resucrages.first(where: { $0.intention == .correctifHypo }) {
            let delai = Int(correctif.heure.timeIntervalSince(basaleTime) / 60)
            return .hypo(delaiMinutes: max(0, delai))
        }
        guard !resucrages.isEmpty else { return .stable }
        return .hypoEvitee(glucides: resucrages.reduce(0) { $0 + $1.glucides })
    }

    // MARK: - Contexte

    private static func tendanceProche(
        _ lectures: [(date: Date, valeur: Int, tendance: TendanceGlycemie?)],
        a instant: Date
    ) -> TendanceGlycemie? {
        lectures.min(by: { abs($0.date.timeIntervalSince(instant)) < abs($1.date.timeIntervalSince(instant)) })?.tendance
    }

    /// Glucides ingérés dans la fenêtre de coucher — collations **et**
    /// resucrages (les deux comptent : c'est du sucre au coucher). Somme si
    /// plusieurs, `nil` si aucun.
    private static func glucidesAutourDuCoucher(
        _ repas: [(heure: Date, glucides: Int)],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)],
        z1: ClosedRange<Date>, z2: ClosedRange<Date>
    ) -> Double? {
        func dansFenetre(_ heure: Date) -> Bool { z1.contains(heure) || z2.contains(heure) }
        let total = repas.filter { dansFenetre($0.heure) }.reduce(0) { $0 + $1.glucides }
            + resucrages.filter { dansFenetre($0.heure) }.reduce(0) { $0 + $1.glucides }
        return total > 0 ? Double(total) : nil
    }

    /// Séance de sport du jour même — la première si plusieurs (contexte
    /// affiché en résumé, détail au tap dans l'UI).
    private static func sportDuJour(
        _ sports: [(debut: Date, resume: SportResume)],
        jour: Date, cal: Calendar
    ) -> SportResume? {
        sports.first { cal.isDate($0.debut, inSameDayAs: jour) }?.resume
    }

    private static func iobAuCoucher(
        _ rapides: [(heure: Date, dose: Double, correction: Bool)],
        a instant: Date,
        config: ConfigEndormissement
    ) -> Double? {
        let injections = rapides
            .filter { $0.heure <= instant }
            .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) }
        let iob = IOBCalculateur.iob(a: instant, injections: injections, diaHeures: config.diaHeures, picMinutes: config.picMinutes)
        return iob > 0.05 ? iob : nil
    }
}
