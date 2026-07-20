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

/// Validation de la dose saisie par rapport au ratio recommandé.
/// L'écart est `doseSaisie - doseSuggeree`.
/// On considère cohérent si l'écart absolu est inférieur à 0.5u.
struct ValidationRatio {
    let doseSaisie: Double
    let doseSuggeree: Double
    let profil: ProfilRatio

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
    static func contexte(
        doseSaisie: Double,
        glucides: Double,
        heure: Date,
        section: SectionRepas,
        contexte: ModelContext?
    ) -> ContexteInsights {
        ContexteInsights(
            validation: validation(doseSaisie: doseSaisie, glucides: glucides, section: section),
            sport: sportRecent(avant: heure, contexte: contexte),
            iob: iobActif(a: heure, contexte: contexte)
        )
    }

    // MARK: Validation ratio (profil configuré)

    private static func validation(doseSaisie: Double, glucides: Double, section: SectionRepas) -> ValidationRatio? {
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
        return ValidationRatio(doseSaisie: doseSaisie, doseSuggeree: suggeree, profil: profilRatio)
    }

    /// Ratio insuline/glucides configuré (grammes couverts par 1u) pour le
    /// moment donné, selon le mode du profil. `nil` si non renseigné.
    private static func ratioConfigure(section: SectionRepas, profil: ProfilUtilisateur) -> Double? {
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
            // Ratio ajusté post-sport = analyse R2, non implémentée → la carte
            // affiche « pas assez de données pour ajuster le ratio ».
            ratioAjuste: nil,
            nombreSeancesHistorique: 0
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
