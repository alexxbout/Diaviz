//
//  RechercheCoucher.swift
//  diaviz
//

import Foundation
import SwiftData

/// Corpus de la recherche **« Comparer à ce soir »** — recalcule le pipeline
/// complet des analyses du coucher (segmentation B1 → fusion B2+B3) sur une
/// fenêtre **élargie à 60 nuits**, sans le reset au changement de dose de
/// lente : la recherche compare à tout l'historique récent, pas seulement à
/// la fenêtre comparable du tableau (cadrage B2 : « la recherche garde tout
/// l'historique »).
///
/// Calcul pur à la volée (millisecondes) — invoqué à l'ouverture de la sheet,
/// jamais persisté.
@MainActor
enum RechercheCoucher {

    /// Fenêtre de recherche (nuits glissantes). Horizon aligné sur le cadrage
    /// B3 (« 60 jours »). Au-delà, les habitudes (dose, sensibilité) ont trop
    /// changé pour que la comparaison éclaire ce soir.
    static let fenetreNuits = 60

    struct Corpus {
        /// Soirs analysables des 60 dernières nuits, toutes doses confondues.
        let soirs: [SoirCoucher]
        /// Nuits B1 correspondantes (courbes) — pour la sheet détail.
        let nuits: [NightChartData]
        let changementDoseRecent: Date?
    }

    /// Contexte « ce soir » connu de l'app sans saisie : dose de lente
    /// courante, charge 7 jours, sport du jour, IOB à l'instant.
    struct ContexteCeSoir {
        let doseLente: Double
        let charge: ChargeActivite
        let sport: SportResume?
        let iob: Double?
    }

    // MARK: - Corpus (60 nuits)

    static func corpus(contexte: ModelContext) -> Corpus {
        let profil = ProfilService.shared.profil
        let cal = Calendar.current
        let debutCourant = ScoreService.debutJourMetabolique()
        let borne = cal.date(byAdding: .day, value: -(fenetreNuits + 1), to: debutCourant) ?? debutCourant
        let borneDose = cal.date(byAdding: .day, value: -120, to: debutCourant) ?? debutCourant

        let cgm = ChargeurFaitsCoucher.cgm(contexte, depuis: borne)
        let lentes = ChargeurFaitsCoucher.lentes(contexte, depuis: borneDose)
        let rapides = ChargeurFaitsCoucher.rapides(contexte, depuis: borne)
        let repas = ChargeurFaitsCoucher.repas(contexte, depuis: borne)
        // B1 sépare repas et resucrages (les repas badgés basculent côté
        // resucrages) ; B2/B3 consomment encore `repas` entier.
        let repasHorsResucrage = ChargeurFaitsCoucher.repasHorsResucrage(contexte, depuis: borne)
        let resucrages = ChargeurFaitsCoucher.resucrages(contexte, depuis: borne)
        let sports = ChargeurFaitsCoucher.sports(contexte, depuis: borne)
        let pauses = ChargeurFaitsCoucher.pauses(contexte, depuis: borne)

        // Segmentation B1 sur la fenêtre élargie.
        var configB1 = ConfigBasale(
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        configB1.fenetreNuits = fenetreNuits
        let analyseB1 = CalculAnalyseBasale.analyser(
            entrees: EntreesBasale(
                lectures: cgm.map { (date: $0.date, valeur: $0.valeur) },
                lentes: lentes,
                rapides: rapides,
                repas: repasHorsResucrage,
                resucrages: resucrages,
                sports: sports.map { (debut: $0.debut, dureeMin: $0.resume.dureeMinutes) },
                pauses: pauses
            ),
            config: configB1
        )

        // Fusion B2+B3 **sans** reset de dose (`changementDoseRecent: nil`).
        let ancrages = ChargeurFaitsCoucher.ancragesNuit(depuis: analyseB1.nightChartData)
        let configEndo = ConfigEndormissement(
            seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
            diaHeures: profil.dureeActionInsulineHeures,
            picMinutes: profil.insulineRapide.picActionMinutes
        )
        let endormissement = CalculAnalyseEndormissement.analyser(
            entrees: EntreesEndormissement(
                nuits: ancrages, lectures: cgm, rapides: rapides,
                repas: repasHorsResucrage, resucrages: resucrages,
                sports: sports, pauses: pauses
            ),
            doseActuelle: analyseB1.doseActuelle,
            changementDoseRecent: nil,
            config: configEndo
        )
        let corrections = CalculAnalyseCorrections.analyser(
            entrees: EntreesCorrections(
                nuits: ancrages, lectures: cgm, rapides: rapides,
                repas: repasHorsResucrage, resucrages: resucrages,
                sports: sports, pauses: pauses
            ),
            changementDoseRecent: nil,
            config: ConfigCorrections(
                cibleHaute: Int(profil.seuilsGlycemiques.hyperglycemie),
                seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
                diaHeures: profil.dureeActionInsulineHeures,
                picMinutes: profil.insulineRapide.picActionMinutes
            )
        )
        let fusion = CalculSituationsCoucher.analyser(
            endormissement: endormissement,
            corrections: corrections,
            timeline: analyseB1.timeline
        )

        return Corpus(
            soirs: fusion.soirs,
            nuits: analyseB1.nightChartData,
            changementDoseRecent: analyseB1.changementDoseRecent
        )
    }

    // MARK: - Contexte de ce soir

    static func contexteCeSoir(contexte: ModelContext, doseLente: Double) -> ContexteCeSoir {
        let maintenant = Date()
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -8, to: maintenant) ?? maintenant
        let sports = ChargeurFaitsCoucher.sports(contexte, depuis: borne)

        let charge = CalculChargeActivite.charge(
            jusqua: maintenant,
            activites: sports.map { (debut: $0.debut, dureeMin: $0.resume.dureeMinutes) }
        )
        let sportDuJour = sports
            .filter { cal.isDate($0.debut, inSameDayAs: maintenant) }
            .max(by: { $0.debut < $1.debut })?.resume

        let iob = IOBService.iobDuHub(a: maintenant, contexte: contexte)

        return ContexteCeSoir(
            doseLente: doseLente,
            charge: charge,
            sport: sportDuJour,
            iob: iob > 0.05 ? iob : nil
        )
    }
}
