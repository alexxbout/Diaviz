//
//  CalculDetailSoiree.swift
//  diaviz
//

import Foundation

// MARK: - Événement de la timeline

/// Un événement de la soirée, affiché sur la timeline verticale de la sheet
/// détail. Ordre chronologique : repas → correction → lente → hypo → réveil.
nonisolated struct EvenementSoiree: Identifiable, Sendable {

    nonisolated enum Genre: Sendable {
        /// Repas du soir (collation, dîner tardif) — jamais un resucrage.
        case repas(glucides: Int)
        /// Resucrage loggé, avec l'intention **déclarée** par l'utilisateur.
        case resucrage(glucides: Int, intention: IntentionResucrage)
        /// Correction rapide au coucher (trigger B3).
        case correction(dose: Double, glycemie: Int?)
        /// Injection de lente — ancre de la nuit. `depuis` = début du palier
        /// de dose courant s'il est récent (« 18u · depuis le 2 juin »).
        case lente(dose: Double, depuis: Date?)
        /// Hypo nocturne — `delaiApresLente` en minutes si postérieure à la lente.
        case hypo(valeur: Int, delaiApresLente: Int?)
        /// Glycémie au réveil (médiane fin de nuit, héritée de B1).
        case reveil(valeur: Int)
    }

    let id = UUID()
    let genre: Genre
    let heure: Date
}

// MARK: - Constat B1 de la nuit

/// Ce que l'analyse basale (B1) a vu de cette nuit précise — pont entre les
/// deux analyses du coucher. Factuel, y compris quand la nuit est exclue
/// (souvent *à cause* de la correction B3, ce qui est une info en soi).
nonisolated enum ConstatB1Nuit: Sendable {
    /// Zone 3 analysée : dérive totale (mg/dL) + catégorie.
    case analysee(derive: Int, categorie: CategorieNuit)
    /// Zone 3 exclue de la régression (resucrage, bolus...) mais un signal
    /// indépendant (hypo/hyper profonde) donne quand même un verdict — pas
    /// de dérive chiffrée fiable à afficher.
    case signalSansDerive(categorie: CategorieNuit)
    /// Statut imposé à la main par l'utilisateur.
    case classeeParVous(libelle: String)
    /// Nuit exclue de B1 — motif brut (`RaisonExclusion.rawValue`).
    case exclue(motif: String)
    /// Pas de données B1 pour cette nuit.
    case indisponible
}

// MARK: - Snapshot de la sheet

/// Snapshot prêt à afficher de la sheet « Détail d'une soirée ». Dérivé du
/// soir fusionné (B2/B3), de la nuit B1 correspondante et des faits bruts de
/// la fenêtre — jamais persisté.
nonisolated struct DetailSoiree: Sendable {
    let soir: SoirCoucher
    let evenements: [EvenementSoiree]
    /// Courbe 21h→07h rééchantillonnée par B1 — vide si nuit B1 absente.
    let courbe: [GlucosePoint]
    let seuilHypo: Int
    /// Courbe d'IOB rapide sur la nuit (pas 15 min, mêmes bornes que `courbe`).
    let courbeIOB: [(date: Date, iob: Double)]
    /// IOB estimé au moment de la première hypo — la note factuelle sous la
    /// courbe (« ~1u encore actif au moment de l'hypo »).
    let iobAuMomentHypo: Double?
    let constatB1: ConstatB1Nuit
}

// MARK: - Calculateur

/// Assembleur de la sheet **« Détail d'une soirée »** : reconstruit la
/// chronologie complète (repas → correction → lente → hypo → réveil) et les
/// courbes de la nuit à partir du soir fusionné, de la `NightChartData` B1
/// et des faits bruts. Pur, jamais persisté, formulations factuelles.
nonisolated enum CalculDetailSoiree {

    static func analyser(
        soir: SoirCoucher,
        nuitB1: NightChartData?,
        rapides: [(heure: Date, dose: Double, correction: Bool)],
        repas: [(heure: Date, glucides: Int)],
        resucrages: [(heure: Date, glucides: Int, intention: IntentionResucrage)] = [],
        changementDoseRecent: Date?,
        config: ConfigEndormissement = ConfigEndormissement()
    ) -> DetailSoiree {
        guard let nuitB1 else {
            // Sans nuit B1 : pas de courbe ni d'ancre lente fiable — on ne
            // montre que le soir lui-même (dégradation gracieuse).
            return DetailSoiree(
                soir: soir, evenements: [], courbe: [],
                seuilHypo: config.seuilHypo, courbeIOB: [], iobAuMomentHypo: nil,
                constatB1: .indisponible
            )
        }

        let L = nuitB1.basaleTime
        let fenetre = L.addingTimeInterval(-3 * 3600)...L.addingTimeInterval(2 * 3600)
        let courbe = nuitB1.glucoseValues

        // Hypos de la nuit — reprises des events B1 (episodes déjà détectés).
        let hypos = nuitB1.events
            .filter { $0.type == .hypo }
            .sorted { $0.time < $1.time }

        var evenements: [EvenementSoiree] = []

        // Repas et resucrages de la soirée (lente −5h → fin de courbe). Le
        // resucrage n'est plus deviné (« repas < 45 min après une hypo ») :
        // c'est un fait de hub à part entière, avec son intention déclarée.
        let finNuit = courbe.last?.time ?? L.addingTimeInterval(9 * 3600)
        let debutSoiree = L.addingTimeInterval(-5 * 3600)
        for r in repas where r.heure >= debutSoiree && r.heure <= finNuit {
            evenements.append(EvenementSoiree(
                genre: .repas(glucides: r.glucides), heure: r.heure
            ))
        }
        for r in resucrages where r.heure >= debutSoiree && r.heure <= finNuit {
            evenements.append(EvenementSoiree(
                genre: .resucrage(glucides: r.glucides, intention: r.intention), heure: r.heure
            ))
        }

        // Corrections rapides dans la fenêtre de coucher.
        for c in rapides where c.correction && fenetre.contains(c.heure) {
            evenements.append(EvenementSoiree(
                genre: .correction(dose: c.dose, glycemie: valeurCourbe(courbe, a: c.heure)),
                heure: c.heure
            ))
        }

        // Lente — ancre de la nuit.
        if nuitB1.basaleDose > 0 {
            evenements.append(EvenementSoiree(
                genre: .lente(dose: nuitB1.basaleDose, depuis: changementDoseRecent), heure: L
            ))
        }

        // Hypos.
        for h in hypos {
            let delai = h.time > L ? Int(h.time.timeIntervalSince(L) / 60) : nil
            evenements.append(EvenementSoiree(
                genre: .hypo(valeur: Int(h.value), delaiApresLente: delai), heure: h.time
            ))
        }

        // Réveil — clôt l'histoire de la nuit.
        if let finCourbe = courbe.last?.time, nuitB1.wakeUpGlucose > 0 {
            evenements.append(EvenementSoiree(
                genre: .reveil(valeur: Int(nuitB1.wakeUpGlucose)), heure: finCourbe
            ))
        }

        evenements.sort { $0.heure < $1.heure }

        // Courbe IOB sur les bornes de la courbe glycémie.
        let courbeIOB = calculerCourbeIOB(rapides: rapides, courbe: courbe, config: config)
        let iobHypo = hypos.first.map {
            iob(a: $0.time, rapides: rapides, config: config)
        }

        return DetailSoiree(
            soir: soir,
            evenements: evenements,
            courbe: courbe,
            seuilHypo: config.seuilHypo,
            courbeIOB: courbeIOB,
            iobAuMomentHypo: (iobHypo ?? 0) > 0.05 ? iobHypo : nil,
            constatB1: constat(nuitB1)
        )
    }

    // MARK: - Constat B1

    private static func constat(_ nuit: NightChartData) -> ConstatB1Nuit {
        if let motif = nuit.motifExclusion {
            return .exclue(motif: motif)
        }
        if let manuel = nuit.classementManuel {
            return .classeeParVous(libelle: manuel.libelle)
        }
        // Zone exclue de la régression mais nuit tout de même verdictée
        // (hypo/hyper profonde) — voir `categorieForcee` dans
        // `CalculAnalyseBasale.analyserNuit`.
        if nuit.slopeZone3 == nil, let categorie = nuit.categorieVerdict {
            return .signalSansDerive(categorie: categorie)
        }
        guard let slope = nuit.slopeZone3,
              let z3 = nuit.zones.first(where: { $0.zone == .nuitProfonde }) else {
            return .indisponible
        }
        let dureeH = z3.timeRange.upperBound.timeIntervalSince(z3.timeRange.lowerBound) / 3600
        let derive = slope * dureeH
        // Catégorie = celle du vrai verdict (`categorieVerdict`), pas un
        // recalcul sur la seule dérive — voir `CarteVerdictNuit` (même bug).
        return .analysee(
            derive: Int(derive.rounded()),
            categorie: nuit.categorieVerdict ?? CalculAnalyseBasale.categorie(deriveMgDl: derive)
        )
    }

    // MARK: - IOB

    /// IOB total à `instant` — seules les injections **déjà faites** comptent
    /// (contrairement à `IOBCalculateur.iob` qui suppose des injections
    /// passées, on balaye ici toute une nuit).
    private static func iob(
        a instant: Date,
        rapides: [(heure: Date, dose: Double, correction: Bool)],
        config: ConfigEndormissement
    ) -> Double {
        let injections = rapides
            .filter { $0.heure <= instant }
            .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) }
        return IOBCalculateur.iob(
            a: instant, injections: injections,
            diaHeures: config.diaHeures, picMinutes: config.picMinutes
        )
    }

    private static func calculerCourbeIOB(
        rapides: [(heure: Date, dose: Double, correction: Bool)],
        courbe: [GlucosePoint],
        config: ConfigEndormissement
    ) -> [(date: Date, iob: Double)] {
        guard let debut = courbe.first?.time, let fin = courbe.last?.time else { return [] }
        var points: [(date: Date, iob: Double)] = []
        var t = debut
        while t <= fin {
            points.append((date: t, iob: iob(a: t, rapides: rapides, config: config)))
            t = t.addingTimeInterval(15 * 60)
        }
        return points
    }

    // MARK: - Outils

    /// Valeur de la courbe rééchantillonnée au plus proche de `t`.
    private static func valeurCourbe(_ courbe: [GlucosePoint], a t: Date) -> Int? {
        courbe.min(by: { abs($0.time.timeIntervalSince(t)) < abs($1.time.timeIntervalSince(t)) })
            .map { Int($0.value.rounded()) }
    }
}
