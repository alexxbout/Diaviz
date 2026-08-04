//
//  InsightsService.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import Foundation
import SwiftData

// MARK: - Modèles d'insights

/// Profil de ratio insuline/glucides actif sur la période actuelle de la journée.
/// Les valeurs sont mockées : on simulerait normalement un profil par tranche horaire.
struct ProfilRatio {
    /// Unités d'insuline par 10g de glucides (ex : 1.0 = 1u/10g).
    let unitesPour10g: Double
    /// Libellé humain du profil actif (ex : "midi", "soir", "matin").
    let libelle: String

    var description: String {
        let formatte = unitesPour10g == floor(unitesPour10g)
            ? String(format: "%.0fu/10g", unitesPour10g)
            : String(format: "%.1fu/10g", unitesPour10g)
        return "\(formatte) profil \(libelle)"
    }
}

/// Écart observé pour un groupe d'ajustement (sport récent, repas gras…)
/// présent sur le repas en cours de saisie — distinct de l'écart « moment »
/// (matin/midi/soir), affiché en plus dans la carte Validation ratio.
struct EcartAjustementObserve: Identifiable {
    var id: String { raison.rawValue }
    let raison: RaisonAjustement
    let ecart: EcartRatioObserve
}

/// Validation de la dose saisie par rapport au ratio recommandé.
/// L'écart est `doseSaisie - doseSuggeree`.
/// On considère cohérent si l'écart absolu est inférieur à 0.5u.
struct ValidationRatio {
    let doseSaisie: Double
    let doseSuggeree: Double
    let profil: ProfilRatio
    /// Écart factuel entre le ratio configuré et un ratio mieux observé
    /// historiquement pour ce moment (mining R1, `CalculRatioObserve`) — `nil`
    /// tant que les données sont insuffisantes (< 30 repas analysés) ou
    /// qu'aucun écart significatif n'a été détecté. Jamais une dose à utiliser :
    /// toujours restitué avec ses dénominateurs bruts.
    let ecartObserve: EcartRatioObserve?
    /// Écarts observés pour chaque raison d'ajustement présente sur ce repas
    /// (sport récent, repas gras…) — groupe séparé du ratio de base, jamais
    /// fusionné (voir `GroupeRatio`).
    let ecartsAjustements: [EcartAjustementObserve]

    init(
        doseSaisie: Double, doseSuggeree: Double, profil: ProfilRatio,
        ecartObserve: EcartRatioObserve? = nil,
        ecartsAjustements: [EcartAjustementObserve] = []
    ) {
        self.doseSaisie = doseSaisie
        self.doseSuggeree = doseSuggeree
        self.profil = profil
        self.ecartObserve = ecartObserve
        self.ecartsAjustements = ecartsAjustements
    }

    var ecart: Double { doseSaisie - doseSuggeree }

    /// 3 états visuels possibles selon le signe et l'amplitude de l'écart.
    enum Etat { case coherente, faible, elevee }

    var etat: Etat {
        if abs(ecart) < 0.5 { return .coherente }
        return ecart < 0 ? .faible : .elevee
    }
}

/// Sport détecté dans la fenêtre récente (3h par défaut).
/// Si `ratioAjuste` est nil, on n'a pas encore assez de données historiques
/// pour proposer un ratio personnalisé après ce type d'activité.
struct SportDetecte {
    let typeSport: String
    let icone: String
    let ilYAMinutes: Int
    let ratioAjuste: ProfilRatio?
    let nombreSeancesHistorique: Int
}

/// Une injection rapide encore active (insuline IOB = "Insulin On Board").
struct InjectionActive: Identifiable {
    let id = UUID()
    let unitesInjectees: Double
    let heureInjection: Date
    let unitesRestantes: Double
}

/// Snapshot d'IOB à un instant donné.
struct IOB {
    /// Total d'unités encore actives. 0 = pas d'IOB.
    let unitesTotales: Double
    /// Détail injection par injection (du plus récent au plus ancien).
    let injections: [InjectionActive]
}

/// Conteneur global retourné par le service.
struct ContexteInsights {
    let validation: ValidationRatio?
    let sport: SportDetecte?
    let iob: IOB?
}

// MARK: - Service

/// Source d'insights contextuels affichés dans la section « Alertes » de
/// `RepasSheet`, dérivés **du hub** (aucun mock) :
/// - **Validation ratio** : dose saisie vs dose issue du ratio *configuré* dans
///   le profil pour le moment de la journée. Factuel — pas le « ratio optimal
///   observé » (analyse R1, non implémentée).
/// - **Sport** : présence d'une activité sportive dans les 3h précédant le
///   repas. Le ratio ajusté post-sport (analyse R2) reste `nil`.
/// - **IOB** : insuline rapide encore active, via `IOBCalculateur` et la DIA du
///   profil — même modèle que la carte « Insuline active » de l'accueil.
///
/// Calculateur sans état : chaque appel relit le hub. Toujours factuel, jamais
/// un conseil de dose.
enum InsightsService {

    /// Fenêtre de détection d'un sport « récent » avant le repas (3h).
    private static let fenetreSport: TimeInterval = 3 * 3600

    // MARK: API publique

    /// Construit le contexte d'insights pour un repas en cours de composition.
    ///
    /// - Parameters:
    ///   - doseSaisie: total d'insuline saisi (aliments + ajustements + correction).
    ///   - glucides: total de glucides du repas (g).
    ///   - heure: instant de référence (T0 — l'instant de saisie).
    ///   - section: moment du repas, pour choisir le ratio en mode `.parMoment`.
    ///   - contexte: contexte du hub (sport + IOB). `nil` → ces deux blocs absents.
    ///   - analyseRatioObserve: mining R1 déjà calculé (`AnalyseRatioService`),
    ///     transmis par l'appelant — pas de recalcul ici (couche agrégée,
    ///     recalculée sur mutation du hub, pas à chaque frappe de saisie).
    ///   - ajustements: ajustements intentionnels du repas en cours (sport
    ///     récent…) — cherche l'écart observé de leur groupe en plus de celui
    ///     du moment, jamais fusionné.
    static func contexte(
        doseSaisie: Double,
        glucides: Double,
        heure: Date,
        section: SectionRepas,
        contexte: ModelContext?,
        analyseRatioObserve: AnalyseRatioObserve = .vide,
        ajustements: [Ajustement] = []
    ) -> ContexteInsights {
        ContexteInsights(
            validation: validation(
                doseSaisie: doseSaisie, glucides: glucides, section: section,
                analyseRatioObserve: analyseRatioObserve, ajustements: ajustements
            ),
            sport: sportRecent(avant: heure, contexte: contexte),
            iob: iobActif(a: heure, contexte: contexte)
        )
    }

    // MARK: Validation ratio (profil configuré)

    private static func validation(
        doseSaisie: Double, glucides: Double, section: SectionRepas,
        analyseRatioObserve: AnalyseRatioObserve, ajustements: [Ajustement]
    ) -> ValidationRatio? {
        guard glucides > 0 else { return nil }
        let profil = ProfilService.shared.profil
        guard let grammesParUnite = ratioConfigure(section: section, profil: profil), grammesParUnite > 0 else {
            // Ratio non renseigné dans le profil → pas de suggestion possible.
            return nil
        }
        let suggeree = glucides / grammesParUnite
        let profilRatio = ProfilRatio(
            unitesPour10g: 10 / grammesParUnite,
            libelle: section.titre.lowercased()
        )
        let sectionRecherchee = profil.modeRatio == .unique ? nil : section
        let ecart = analyseRatioObserve.sections.first { $0.groupe == .moment(sectionRecherchee) }?.ecart

        // Écarts des groupes d'ajustement présents sur ce repas — jamais
        // fusionnés avec celui du moment (voir GroupeRatio).
        let raisons = Set(ajustements.map(\.raison))
        let ecartsAjustements = raisons.compactMap { raison -> EcartAjustementObserve? in
            guard let ecartRaison = analyseRatioObserve.sections.first(where: { $0.groupe == .ajustement(raison) })?.ecart
            else { return nil }
            return EcartAjustementObserve(raison: raison, ecart: ecartRaison)
        }

        return ValidationRatio(
            doseSaisie: doseSaisie, doseSuggeree: suggeree, profil: profilRatio,
            ecartObserve: ecart, ecartsAjustements: ecartsAjustements
        )
    }

    /// Ratio insuline/glucides configuré (grammes couverts par 1u) pour le
    /// moment donné, selon le mode du profil. `nil` si non renseigné.
    /// Non-`private` : réutilisé par `AnalyseRatioService` pour comparer les
    /// repas historiques au ratio configuré actuel (mining R1).
    static func ratioConfigure(section: SectionRepas, profil: ProfilUtilisateur) -> Double? {
        switch profil.modeRatio {
        case .unique:
            return profil.ratioUnique
        case .parMoment:
            switch section {
            case .petitDejeuner: return profil.ratiosParMoment.petitDejeuner
            case .dejeuner:      return profil.ratiosParMoment.dejeuner
            case .enCas:         return profil.ratiosParMoment.gouter
            // Pas de ratio dédié pour « Nuit » (pas de champ profil) — on
            // retombe sur celui du dîner, la période temporellement la plus
            // proche.
            case .diner, .nuit:  return profil.ratiosParMoment.diner
            }
        }
    }

    // MARK: Sport récent (présence uniquement)

    private static func sportRecent(avant instant: Date, contexte: ModelContext?) -> SportDetecte? {
        guard let contexte else { return nil }
        let depuis = instant.addingTimeInterval(-fenetreSport)
        let descripteur = FetchDescriptor<ActiviteSportive>(
            predicate: #Predicate { $0.dateDebut >= depuis && $0.dateDebut <= instant },
            sortBy: [SortDescriptor(\.dateDebut, order: .reverse)]
        )
        guard let activite = try? contexte.fetch(descripteur).first else { return nil }
        let minutes = Int(instant.timeIntervalSince(activite.dateDebut) / 60)
        return SportDetecte(
            typeSport: activite.type.rawValue,
            icone: activite.type.icone,
            ilYAMinutes: minutes,
            ratioAjuste: ratioSportConfigure(type: activite.type, ilYAMinutes: minutes),
            nombreSeancesHistorique: 0
        )
    }

    /// Ratio post-sport **saisi par l'utilisateur** dans le profil (et non
    /// dérivé de son historique — l'analyse R2 reste à faire). `nil` si aucun
    /// ratio n'est configuré pour ce sport, ou si la séance est déjà sortie de
    /// la fenêtre d'effet réglée : la carte retombe alors sur son message
    /// « pas assez de données ».
    private static func ratioSportConfigure(type: TypeSport, ilYAMinutes: Int) -> ProfilRatio? {
        let ratios = ProfilService.shared.profil.ratiosSportEffectifs
        guard Double(ilYAMinutes) <= ratios.fenetreEffetHeures * 60,
              let grammesParUnite = ratios.ratio(pour: type),
              grammesParUnite > 0
        else { return nil }

        return ProfilRatio(
            unitesPour10g: 10 / grammesParUnite,
            libelle: "post-\(type.rawValue.lowercased())"
        )
    }

    // MARK: IOB (insuline rapide active)

    private static func iobActif(a instant: Date, contexte: ModelContext?) -> IOB? {
        guard let contexte else { return nil }
        let profil = ProfilService.shared.profil
        let dia = profil.dureeActionInsulineHeures
        let pic = profil.insulineRapide.picActionMinutes
        let depuis = instant.addingTimeInterval(-dia * 3600)
        let descripteur = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.heure >= depuis && $0.heure < instant },
            sortBy: [SortDescriptor(\.heure, order: .reverse)]
        )
        // Le filtre « rapide » se fait en Swift (comparer un enum en #Predicate
        // SwiftData est fragile ; le volume est trivial) — même choix qu'`IOBService`.
        let rapides = ((try? contexte.fetch(descripteur)) ?? []).filter { $0.type != .lente }
        guard !rapides.isEmpty else { return nil }

        let td = dia * 60
        var actives: [InjectionActive] = []
        var total = 0.0
        for injection in rapides {
            let minutes = instant.timeIntervalSince(injection.heure) / 60
            let restant = injection.dose * IOBCalculateur.fractionRestante(
                minutes: minutes, diaMinutes: td, picMinutes: pic
            )
            guard restant > 0.05 else { continue }
            actives.append(InjectionActive(
                unitesInjectees: injection.dose,
                heureInjection: injection.heure,
                unitesRestantes: restant
            ))
            total += restant
        }
        guard total > 0.05 else { return nil }
        return IOB(unitesTotales: total, injections: actives)
    }
}
