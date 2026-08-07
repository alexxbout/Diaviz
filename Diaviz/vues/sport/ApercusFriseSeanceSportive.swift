//
//  ApercusFriseSeanceSportive.swift
//  diaviz
//

#if DEBUG

import SwiftUI

/// Jeux d'aperçu de `FriseSeanceSportive` — un scénario par cas de verdict,
/// avec une courbe glycémique cohérente avec ce que l'algorithme doit en
/// conclure.
///
/// Les verdicts ne sont **jamais posés à la main** : chaque scénario fait
/// passer ses données par `CalculVerdictsResucrage`, exactement comme
/// `ActivitesSportService`. Un aperçu qui affiche le mauvais verdict signale
/// donc un vrai défaut de l'algorithme, pas une incohérence de fixture.
enum ApercusFrise {

    // MARK: - Construction d'un scénario

    /// Ancre de courbe : minutes depuis le début de l'activité → glycémie.
    /// Les points intermédiaires sont interpolés toutes les 5 min, cadence
    /// réelle d'un Dexcom.
    typealias Ancre = (minutes: Double, valeur: Double)

    struct Scenario {
        let activite: ActiviteSportive
        let reponse: ReponseGlycemiqueSport
        let evenements: [EvenementActivite]
    }

    /// Heure de départ fixe — une séance de fin d'après-midi, pour que les
    /// libellés horaires des aperçus soient stables d'un lancement à l'autre.
    private static var depart: Date {
        Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// - Parameters:
    ///   - dureeMinutes: durée d'effort net.
    ///   - courbe: ancres de la courbe glycémique.
    ///   - resucrages: `(minutes, intention, grammes)`.
    ///   - corrections: `(minutes, dose)` — insuline, jamais jugée.
    ///   - pauses: `(minutesDébut, minutesFin)`.
    ///   - preSport: `(nom, grammes)` des aliments pris avant l'effort.
    ///   - trouCgm: intervalle `(début, fin)` en minutes sans aucune mesure.
    static func scenario(
        type: TypeSport = .course,
        dureeMinutes: Int = 60,
        courbe: [Ancre],
        resucrages: [(minutes: Double, intention: IntentionResucrage, grammes: Int)] = [],
        corrections: [(minutes: Double, dose: Double)] = [],
        pauses: [(debut: Double, fin: Double)] = [],
        preSport: [(nom: String, grammes: Int)] = [],
        trouCgm: (debut: Double, fin: Double)? = nil
    ) -> Scenario {
        let debut = depart

        let activite = ActiviteSportive(
            type: type,
            dateDebut: debut,
            dureeMinutes: dureeMinutes,
            intensite: .moderee,
            alimentsPreSport: preSport.map {
                Aliment(emoji: "🍎", nom: $0.nom, quantite: 100, glucides: $0.grammes, insuline: 0)
            },
            structureEffort: type.categorie == .cardio ? .continu : nil,
            pauses: pauses.map {
                IntervallePauseSeance(
                    debut: debut.addingTimeInterval($0.debut * 60),
                    fin: debut.addingTimeInterval($0.fin * 60)
                )
            },
            source: .manuel,
            iobAuDebut: 1.2
        )

        let points = interpoler(courbe, trou: trouCgm)

        let prises = resucrages.enumerated().map { index, r in
            PriseAJuger(
                id: "resucrage-\(index)",
                date: debut.addingTimeInterval(r.minutes * 60),
                intention: r.intention,
                glucides: r.grammes
            )
        }

        let seuils = ProfilService.shared.profil.seuilsGlycemiques
        let resultats = CalculVerdictsResucrage.juger(
            prises: prises,
            points: points.map { PointGlycemie(date: debut.addingTimeInterval($0.minutes * 60), valeur: $0.valeur) },
            bornes: BornesVerdict(
                hypoglycemie: seuils.hypoglycemie,
                hyperglycemie: seuils.hyperglycemie
            ),
            finEffort: activite.dateFin,
            correctionsInsuline: corrections.map { debut.addingTimeInterval($0.minutes * 60) }
        )
        let parId = Dictionary(uniqueKeysWithValues: resultats.map { ($0.id, $0) })

        var evenements: [EvenementActivite] = prises.enumerated().map { index, prise in
            EvenementActivite(
                id: prise.id,
                date: prise.date,
                nature: .resucrage(prise.intention),
                detail: "\(resucrages[index].grammes)g",
                pendantPause: activite.pauses.contains { $0.debut <= prise.date && prise.date <= $0.fin },
                resultat: parId[prise.id]
            )
        }

        evenements += corrections.enumerated().map { index, c in
            let date = debut.addingTimeInterval(c.minutes * 60)
            return EvenementActivite(
                id: "correction-\(index)",
                date: date,
                nature: .correction,
                detail: c.dose.doseInsulineFormatee,
                pendantPause: activite.pauses.contains { $0.debut <= date && date <= $0.fin }
            )
        }

        let pointsCgm = points.map {
            PointCgmSport(secondesDepuisDebut: $0.minutes * 60, valeur: $0.valeur)
        }
        let dureeSec = Double(dureeMinutes) * 60
        let reponse = ReponseGlycemiqueSport(
            pointsCgm: pointsCgm,
            glycemieDebut: valeurA(0, dans: points),
            glycemieFin: valeurA(dureeSec / 60, dans: points),
            deltaMgDl: valeurA(dureeSec / 60, dans: points) - valeurA(0, dans: points)
        )

        return Scenario(
            activite: activite,
            reponse: reponse,
            evenements: evenements.sorted { $0.date < $1.date }
        )
    }

    // MARK: - Courbe

    /// Interpole les ancres toutes les 5 min. `trou` retire les mesures d'un
    /// intervalle, pour exercer le cas « couverture CGM insuffisante ».
    private static func interpoler(
        _ ancres: [Ancre],
        trou: (debut: Double, fin: Double)?
    ) -> [(minutes: Double, valeur: Double)] {
        guard let premiere = ancres.first, let derniere = ancres.last else { return [] }
        var points: [(minutes: Double, valeur: Double)] = []
        var t = premiere.minutes
        while t <= derniere.minutes {
            if let trou, t >= trou.debut, t <= trou.fin {
                t += 5
                continue
            }
            points.append((t, valeurA(t, dans: ancres)))
            t += 5
        }
        return points
    }

    private static func valeurA(_ minutes: Double, dans ancres: [(minutes: Double, valeur: Double)]) -> Double {
        guard let premiere = ancres.first, let derniere = ancres.last else { return 0 }
        if minutes <= premiere.minutes { return premiere.valeur }
        if minutes >= derniere.minutes { return derniere.valeur }
        for i in 1..<ancres.count where ancres[i].minutes >= minutes {
            let a = ancres[i - 1], b = ancres[i]
            let plage = b.minutes - a.minutes
            guard plage > 0 else { return b.valeur }
            let ratio = (minutes - a.minutes) / plage
            return a.valeur + (b.valeur - a.valeur) * ratio
        }
        return derniere.valeur
    }
}

// MARK: - Enveloppe d'aperçu

private struct ApercuFrise: View {
    let titre: String
    let attendu: String
    let scenario: ApercusFrise.Scenario

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre)
                        .font(.headline)
                    Text("Attendu : \(attendu)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                FriseSeanceSportive(
                    reponse: scenario.reponse,
                    activite: scenario.activite,
                    evenements: scenario.evenements
                )
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Correctif hypo

#Preview("01 · Correctif — remonté") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 145), (0, 140), (30, 105), (45, 62), (60, 95), (90, 120)],
        resucrages: [(45, .correctifHypo, 15)]
    )
    ApercuFrise(titre: "Hypo en fin d'effort, resucrage efficace", attendu: "Remonté", scenario: s)
}

#Preview("02 · Correctif — remonté trop haut") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 130), (0, 120), (30, 80), (40, 58), (70, 150), (90, 215)],
        resucrages: [(40, .correctifHypo, 45)]
    )
    ApercuFrise(titre: "Resucrage massif sur hypo", attendu: "Remonté trop haut", scenario: s)
}

#Preview("03 · Correctif — insuffisant") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 120), (0, 110), (30, 75), (40, 58), (70, 64), (90, 68)],
        resucrages: [(40, .correctifHypo, 8)]
    )
    ApercuFrise(titre: "Resucrage trop léger", attendu: "Insuffisant", scenario: s)
}

// MARK: - Préventif maintien

#Preview("04 · Maintien — maintenu") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 150), (0, 145), (20, 128), (40, 132), (60, 138), (90, 140)],
        resucrages: [(20, .preventifMaintien, 15)],
        preSport: [("Banane", 20)]
    )
    ApercuFrise(titre: "Course d'une heure, glycémie tenue", attendu: "Maintenu", scenario: s)
}

#Preview("05 · Maintien — chute non enrayée (CGM)") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 140), (0, 132), (20, 110), (40, 78), (55, 62), (75, 70), (90, 85)],
        resucrages: [(20, .preventifMaintien, 12)]
    )
    ApercuFrise(titre: "Le maintien n'a pas tenu", attendu: "Chute non enrayée", scenario: s)
}

#Preview("06 · Maintien — chute non enrayée (correctif après)") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 145), (0, 138), (20, 120), (40, 85), (50, 63), (75, 110), (90, 125)],
        resucrages: [(20, .preventifMaintien, 12), (50, .correctifHypo, 15)]
    )
    ApercuFrise(
        titre: "Un correctif hypo suit le maintien",
        attendu: "Chute non enrayée (pas « non évaluable »)",
        scenario: s
    )
}

#Preview("07 · Maintien — monté trop haut") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 150), (0, 148), (20, 140), (45, 195), (60, 210), (90, 190)],
        resucrages: [(20, .preventifMaintien, 40)]
    )
    ApercuFrise(titre: "Maintien surdosé", attendu: "Monté trop haut", scenario: s)
}

// MARK: - Préventif anti-chute

#Preview("08 · Anti-chute — chute évitée") {
    let s = ApercusFrise.scenario(
        type: .musculation,
        dureeMinutes: 50,
        courbe: [(-30, 130), (0, 125), (15, 105), (25, 118), (50, 130), (80, 135)],
        resucrages: [(15, .preventifAntiChute, 10)]
    )
    ApercuFrise(titre: "Musculation, chute anticipée", attendu: "Chute évitée", scenario: s)
}

#Preview("09 · Anti-chute — chute non enrayée") {
    let s = ApercusFrise.scenario(
        type: .musculation,
        dureeMinutes: 50,
        courbe: [(-30, 120), (0, 112), (15, 95), (30, 66), (50, 82), (80, 100)],
        resucrages: [(15, .preventifAntiChute, 8)]
    )
    ApercuFrise(titre: "Dose insuffisante", attendu: "Chute non enrayée", scenario: s)
}

#Preview("10 · Anti-chute — monté trop haut") {
    let s = ApercusFrise.scenario(
        type: .musculation,
        dureeMinutes: 50,
        courbe: [(-30, 140), (0, 138), (15, 132), (35, 200), (50, 215), (80, 195)],
        resucrages: [(15, .preventifAntiChute, 35)]
    )
    ApercuFrise(titre: "Anti-chute surdosé", attendu: "Monté trop haut", scenario: s)
}

// MARK: - Épisodes et cas limites

#Preview("11 · Non évaluable — deux prises rapprochées") {
    let s = ApercusFrise.scenario(
        type: .musculation,
        dureeMinutes: 50,
        courbe: [(-30, 125), (0, 118), (15, 98), (30, 92), (50, 105), (80, 115)],
        resucrages: [(15, .preventifAntiChute, 8), (32, .preventifAntiChute, 8)]
    )
    ApercuFrise(
        titre: "Deux anti-chute à 17 min d'écart",
        attendu: "Non évaluable puis Chute évitée",
        scenario: s
    )
}

#Preview("12 · Épisode — série de trois prises") {
    let s = ApercusFrise.scenario(
        dureeMinutes: 90,
        courbe: [(-30, 150), (0, 145), (20, 120), (40, 108), (60, 102), (90, 115), (120, 125)],
        resucrages: [
            (20, .preventifMaintien, 10),
            (40, .preventifMaintien, 10),
            (60, .preventifMaintien, 10)
        ]
    )
    ApercuFrise(
        titre: "Supplémentation répétée sur une sortie longue",
        attendu: "Un seul épisode, seule la dernière jugée",
        scenario: s
    )
}

#Preview("13 · Indéterminé — trou CGM") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 140), (0, 130), (30, 95), (45, 68), (60, 100), (90, 120)],
        resucrages: [(45, .correctifHypo, 15)],
        trouCgm: (45, 90)
    )
    ApercuFrise(titre: "Capteur muet après la prise", attendu: "Indéterminé", scenario: s)
}

#Preview("14 · Prise pendant une pause") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 140), (0, 135), (25, 95), (35, 64), (55, 105), (90, 125)],
        resucrages: [(35, .correctifHypo, 15)],
        pauses: [(33, 42)]
    )
    ApercuFrise(
        titre: "Séance mise en pause pour se resucrer",
        attendu: "Remonté, mention « en pause »",
        scenario: s
    )
}

#Preview("15 · Prise avant le début de l'effort") {
    let s = ApercusFrise.scenario(
        courbe: [(-40, 105), (-15, 118), (0, 140), (30, 132), (60, 128), (90, 130)],
        resucrages: [(-15, .preventifMaintien, 15)]
    )
    ApercuFrise(titre: "Maintien pris avant de partir", attendu: "Maintenu", scenario: s)
}

#Preview("16 · Prise juste avant la fin (plancher 30 min)") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 140), (0, 135), (40, 100), (55, 88), (70, 110), (90, 120)],
        resucrages: [(55, .preventifMaintien, 12)]
    )
    ApercuFrise(
        titre: "Maintien à 5 min de la fin",
        attendu: "Fenêtre ramenée à 30 min",
        scenario: s
    )
}

// MARK: - Contexte de séance

#Preview("17 · Séance sans aucun événement") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 140), (0, 135), (30, 120), (60, 125), (90, 130)]
    )
    ApercuFrise(titre: "Rien à signaler", attendu: "Liste vide, pas de lien d'explication", scenario: s)
}

#Preview("18 · Pré-sport seul") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 115), (0, 145), (30, 130), (60, 122), (90, 128)],
        preSport: [("Banane", 20)]
    )
    ApercuFrise(titre: "Collation avant l'effort", attendu: "Une ligne, aucun verdict", scenario: s)
}

#Preview("19 · Corrections d'insuline seules") {
    let s = ApercusFrise.scenario(
        type: .musculation,
        dureeMinutes: 50,
        courbe: [(-30, 180), (0, 195), (20, 210), (40, 175), (60, 150), (80, 140)],
        corrections: [(20, 1.5), (45, 1.0)]
    )
    ApercuFrise(titre: "Muscu en hyper, corrections", attendu: "Aucun verdict (insuline non jugée)", scenario: s)
}

#Preview("20 · Séance dense — huit événements") {
    let s = ApercusFrise.scenario(
        dureeMinutes: 120,
        courbe: [
            (-30, 150), (0, 145), (20, 118), (35, 92), (50, 105),
            (65, 88), (80, 112), (95, 96), (120, 118), (150, 130)
        ],
        resucrages: [
            (20, .preventifMaintien, 12),
            (50, .preventifMaintien, 12),
            (65, .correctifHypo, 15),
            (95, .preventifAntiChute, 10),
            (115, .preventifAntiChute, 10)
        ],
        corrections: [(40, 1.0), (105, 0.5)],
        pauses: [(63, 70)],
        preSport: [("Banane", 20)]
    )
    ApercuFrise(
        titre: "Sortie longue chargée",
        attendu: "Lisibilité de la liste et de la courbe",
        scenario: s
    )
}

// MARK: - Interaction avec les corrections d'insuline
//
// L'app ne juge jamais une dose d'insuline, mais sa présence dans la fenêtre
// d'un resucrage invalide le verdict de celui-ci : deux effets opposés s'y
// mélangent. Ces aperçus vérifient que la règle s'applique au bon moment —
// et seulement au bon moment.

#Preview("21 · Correction dans la fenêtre — anti-chute") {
    let s = ApercusFrise.scenario(
        type: .musculation,
        dureeMinutes: 50,
        courbe: [(-30, 130), (0, 125), (15, 108), (30, 78), (45, 66), (65, 88), (80, 100)],
        resucrages: [(15, .preventifAntiChute, 10)],
        corrections: [(28, 1.0)]
    )
    ApercuFrise(
        titre: "Une correction s'intercale après l'anti-chute",
        attendu: "Non évaluable — l'insuline invalide, surtout pas « chute non enrayée »",
        scenario: s
    )
}

#Preview("22 · Correction juste avant la prise") {
    let s = ApercusFrise.scenario(
        type: .musculation,
        dureeMinutes: 50,
        courbe: [(-30, 190), (0, 185), (10, 160), (25, 118), (40, 128), (55, 135), (80, 140)],
        resucrages: [(25, .preventifAntiChute, 10)],
        corrections: [(5, 1.5)]
    )
    ApercuFrise(
        titre: "Correction 20 min avant le resucrage",
        attendu: "Chute évitée — hors fenêtre, la règle ne s'applique pas",
        scenario: s
    )
}

#Preview("23 · Correction juste après la fenêtre") {
    let s = ApercusFrise.scenario(
        type: .musculation,
        dureeMinutes: 60,
        courbe: [(-30, 125), (0, 120), (15, 100), (30, 112), (45, 135), (60, 175), (90, 160)],
        resucrages: [(15, .preventifAntiChute, 12)],
        corrections: [(48, 1.0)]
    )
    ApercuFrise(
        titre: "Correction 33 min après la prise (fenêtre : 30 min)",
        attendu: "Chute évitée — la borne de fenêtre tient",
        scenario: s
    )
}

#Preview("24 · Correction dans une fenêtre longue de maintien") {
    let s = ApercusFrise.scenario(
        dureeMinutes: 90,
        courbe: [(-30, 145), (0, 140), (15, 128), (40, 165), (60, 190), (90, 150), (120, 135)],
        resucrages: [(15, .preventifMaintien, 15)],
        corrections: [(55, 1.5)]
    )
    ApercuFrise(
        titre: "Maintien jugé sur 75 min, correction au milieu",
        attendu: "Non évaluable — la fenêtre longue expose davantage à l'insuline",
        scenario: s
    )
}

#Preview("25 · Correction invalide un correctif hypo") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 130), (0, 122), (25, 85), (35, 62), (55, 120), (75, 185), (90, 170)],
        resucrages: [(35, .correctifHypo, 20)],
        corrections: [(58, 1.0)]
    )
    ApercuFrise(
        titre: "Resucrage d'hypo, puis correction du rebond",
        attendu: "Non évaluable — même un correctif hypo n'y échappe pas",
        scenario: s
    )
}

#Preview("26 · Correction pendant une pause") {
    let s = ApercusFrise.scenario(
        courbe: [(-30, 150), (0, 145), (20, 175), (35, 205), (50, 170), (70, 140), (90, 132)],
        resucrages: [(20, .preventifMaintien, 12)],
        corrections: [(38, 1.5)],
        pauses: [(35, 45)]
    )
    ApercuFrise(
        titre: "Séance en pause, correction d'un pic",
        attendu: "Non évaluable, mentions « en pause » sur les deux lignes",
        scenario: s
    )
}

#Preview("27 · Deux corrections encadrant un resucrage") {
    let s = ApercusFrise.scenario(
        dureeMinutes: 90,
        courbe: [(-30, 200), (0, 195), (20, 150), (40, 105), (55, 88), (75, 120), (110, 145)],
        resucrages: [(40, .preventifAntiChute, 10)],
        corrections: [(10, 2.0), (50, 0.5)]
    )
    ApercuFrise(
        titre: "Une correction avant, une pendant",
        attendu: "Non évaluable — seule celle dans la fenêtre compte",
        scenario: s
    )
}

#endif
