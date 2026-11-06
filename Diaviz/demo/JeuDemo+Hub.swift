//
//  JeuDemo+Hub.swift
//  diaviz
//
//  Insertion du jeu fictif dans un hub SwiftData — app « Diaviz Démo » et
//  aperçus de développement. Jamais appelé par la vraie app.
//

#if DEBUG
import Foundation
import SwiftData

extension JeuDemo {

    /// Date du changement de ratio du dîner (profil + historique).
    var dateChangementRatioDiner: Date? {
        changements.first { $0.parametre == .ratioDiner }?.date
    }

    var profil: ProfilUtilisateur {
        ProfilUtilisateur(
            prenom: Self.prenom,
            poidsKg: 64,
            insulineRapide: .fiasp,
            insulineLente: .lantus,
            dureeActionInsulineHeures: 4,
            modeRatio: .parMoment,
            ratioUnique: nil,
            ratiosParMoment: RatiosParMoment(
                petitDejeuner: Self.ratiosConfigures.petitDejeuner,
                dejeuner: Self.ratiosConfigures.dejeuner,
                gouter: Self.ratiosConfigures.gouter,
                diner: Self.ratiosConfigures.dinerApres
            ),
            datesChangementRatio: DatesChangementRatio(diner: dateChangementRatioDiner),
            ratioCorrection: Self.ratioCorrection,
            ratiosSport: RatiosSport(parType: [TypeSport.course.rawValue: Self.ratioSportCourse]),
            horairesRepas: HorairesRepas.defaut(),
            seuilsGlycemiques: SeuilsGlycemiques(),
            preferencesAvancees: PreferencesAvancees()
        )
    }

    /// Insère tout le jeu (profil compris) dans `contexte`, puis enregistre.
    func inserer(dans contexte: ModelContext) {
        contexte.insert(profil)
        for c in changements {
            contexte.insert(ChangementParametre(
                date: c.date, cle: CleParametre(parametre: c.parametre),
                ancienneValeur: c.ancien, nouvelleValeur: c.nouveau
            ))
        }

        var precedente: (date: Date, valeur: Int)?
        for g in glycemies {
            var tendance: TendanceGlycemie?
            var taux: Double?
            if let p = precedente, g.date.timeIntervalSince(p.date) <= 600 {
                let parMinute = Double(g.valeur - p.valeur) / (g.date.timeIntervalSince(p.date) / 60)
                taux = parMinute
                tendance = switch parMinute {
                case 2...: .forteHausse
                case 1..<2: .hausse
                case -1..<1: .stable
                case -2 ..< -1: .baisse
                default: .forteBaisse
                }
            }
            contexte.insert(GlucoseReading(date: g.date, valeur: g.valeur, tendance: tendance,
                                           tauxVariation: taux, source: .healthkit))
            precedente = g
        }

        let horaires = HorairesRepas.defaut()
        let zones: [(ZoneInjection, CoteInjection)] = [(.ventre, .gauche), (.ventre, .droite), (.bras, .gauche), (.bras, .droite)]
        var repasModeles: [Repas] = []
        for (n, r) in repas.enumerated() {
            let modele = Repas(
                id: r.id, heure: r.heure,
                aliments: r.aliments.map {
                    Aliment(emoji: $0.emoji, nom: $0.nom, quantite: $0.quantite, glucides: $0.glucides, insuline: 0)
                },
                doseGlobale: r.dose,
                ajustements: r.apresSport.map {
                    [Ajustement(raison: .sportRecent, valeur: 0, typeSportDetecte: $0.rawValue)]
                } ?? []
            )
            contexte.insert(modele)
            repasModeles.append(modele)
            if let bolus = injections.first(where: { $0.repasId == r.id }) {
                let site = zones[n % zones.count]
                contexte.insert(Injection(
                    id: bolus.id, type: .rapideRepas, dose: bolus.dose, heure: bolus.heure,
                    zoneInjection: site.0, coteInjection: site.1, repasAssocieId: r.id,
                    labelRepas: SectionRepas(heure: r.heure, horaires: horaires).titre,
                    emojiRepas: modele.emojiPrincipal, motif: .repas, source: .manuel
                ))
            }
        }
        for (n, i) in injections.enumerated() where i.repasId == nil {
            let lente = i.type == .lente
            contexte.insert(Injection(
                id: i.id, type: i.type, dose: i.dose, heure: i.heure,
                zoneInjection: lente ? (n % 2 == 0 ? .cuisse : .fesse) : .ventre,
                coteInjection: n % 2 == 0 ? .gauche : .droite,
                glycemieAuMoment: i.glycemie,
                motif: lente ? .basale : .correction, source: .manuel
            ))
        }
        for r in resucrages {
            contexte.insert(Resucrage(
                id: r.id, date: r.date, intention: .correctifHypo,
                aliments: [Aliment(emoji: r.aliment.emoji, nom: r.aliment.nom, quantite: r.aliment.quantite,
                                   glucides: r.aliment.glucides, insuline: 0, resucrage: true)]
            ))
        }
        for s in seances {
            contexte.insert(ActiviteSportive(
                id: s.id, type: s.type, dateDebut: s.debut, dureeMinutes: s.dureeMinutes, intensite: s.intensite,
                source: .healthKit,
                healthKitData: HealthKitWorkoutData(
                    workoutUUID: s.workoutUUID, fcMoyenne: s.fcMoyenne, fcMax: s.fcPic + 3,
                    caloriesActives: s.calories, distanceMetres: s.distanceMetres, sourceAppareil: "Apple Watch"
                )
            ))
        }
        try? contexte.save()

        // Insuline active au début de chaque repas, comme à la saisie
        // (avant le bolus du repas lui-même).
        for modele in repasModeles {
            let iob = IOBService.iobDuHub(a: modele.heure.addingTimeInterval(-60), contexte: contexte)
            modele.iobAuDebut = iob > 0.05 ? iob : nil
        }
        try? contexte.save()
    }
}
#endif
