//
//  InsightsService.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import Foundation
import SwiftData

// MARK: - Modèles d'insights

/// Profil de ratio insuline/glucides actif sur la période actuelle de la
/// journée, tel qu'il est **configuré dans le profil**.
struct ProfilRatio {
    /// Grammes de glucides couverts par 1 unité d'insuline (ex : 12 = 1u/12g)
    /// — même sens et même unité que `RatiosParMoment` / `RatiosSport` dans le
    /// profil.
    ///
    /// L'affichage utilisait auparavant l'inverse (« 0.8u/10g »), une valeur
    /// que l'utilisateur ne saisit nulle part et doit convertir de tête pour
    /// la rapprocher de son réglage.
    let grammesParUnite: Double
    /// Libellé humain du profil actif (ex : "midi", "soir", "matin").
    let libelle: String

    var description: String {
        let formatte = grammesParUnite == floor(grammesParUnite)
            ? String(format: "1u/%.0fg", grammesParUnite)
            : String(format: "1u/%.1fg", grammesParUnite)
        return "\(formatte) profil \(libelle)"
    }
}

/// Validation de la dose saisie par rapport au ratio recommandé.
/// L'écart est `doseSaisie - doseSuggeree`.
/// On considère cohérent si l'écart absolu est inférieur à 0.5u.
struct ValidationRatio {
    /// Dose **de base** du repas, celle qui prétend couvrir les glucides —
    /// hors ajustements et hors correction d'hyperglycémie. C'est la seule
    /// comparable au ratio : un ajustement est une déviation volontaire, une
    /// correction répond à la glycémie du moment, ni l'un ni l'autre ne
    /// prétend couvrir des glucides.
    let doseSaisie: Double
    let doseSuggeree: Double
    let profil: ProfilRatio
    /// Somme signée des ajustements intentionnels du repas (0 = aucun).
    /// Exclue du verdict, rapportée à part : l'app n'a aucune base pour
    /// juger une déviation décidée par l'utilisateur.
    let ajustements: Double
    /// Glucides du repas (g) — sert à exprimer le ratio réellement appliqué
    /// une fois les ajustements inclus.
    let glucides: Double
    /// `true` quand le ratio en vigueur est celui d'une séance récente et non
    /// celui du moment de la journée. Le mining R1 ne couvrant que les ratios
    /// par moment, ses observations sont alors hors sujet et masquées.
    let ratioSportApplique: Bool
    /// Écart factuel entre le ratio configuré et un ratio mieux observé
    /// historiquement pour ce moment (mining R1, `CalculRatioObserve`) — `nil`
    /// tant qu'aucune tranche n'atteint `CalculRatioObserve.effectifMinimalBucket`
    /// ou qu'aucun écart significatif n'a été détecté. Jamais une dose à
    /// utiliser : toujours restitué avec ses dénominateurs bruts.
    let ecartObserve: EcartRatioObserve?
    /// Repas déjà exploitables dans le groupe (moment) de ce repas — affiché
    /// tel quel faute d'écart à signaler, pour ne pas rester muet.
    let effectifGroupe: Int

    init(
        doseSaisie: Double, doseSuggeree: Double, profil: ProfilRatio,
        ajustements: Double = 0,
        glucides: Double = 0,
        ratioSportApplique: Bool = false,
        ecartObserve: EcartRatioObserve? = nil,
        effectifGroupe: Int = 0
    ) {
        self.doseSaisie = doseSaisie
        self.doseSuggeree = doseSuggeree
        self.profil = profil
        self.ajustements = ajustements
        self.glucides = glucides
        self.ratioSportApplique = ratioSportApplique
        self.ecartObserve = ecartObserve
        self.effectifGroupe = effectifGroupe
    }

    var ecart: Double { doseSaisie - doseSuggeree }

    /// Ratio réellement appliqué au repas une fois les ajustements inclus
    /// (grammes couverts par 1u) — un **fait**, jamais confronté à un seuil :
    /// il ne mesure plus le ratio configuré mais l'écart volontaire qu'on lui
    /// a fait subir. `nil` si aucun ajustement, ou si la dose totale tombe à
    /// zéro (rien à rapporter).
    var ratioEffectifApresAjustement: Double? {
        guard ajustements != 0, glucides > 0 else { return nil }
        let totalCouvrant = doseSaisie + ajustements
        guard totalCouvrant > 0 else { return nil }
        return glucides / totalCouvrant
    }

    /// 3 états visuels possibles selon le signe et l'amplitude de l'écart.
    enum Etat { case coherente, faible, elevee }

    var etat: Etat {
        if abs(ecart) < 0.5 { return .coherente }
        return ecart < 0 ? .faible : .elevee
    }
}

/// Sport détecté dans la fenêtre récente (3h par défaut) — un **fait** du
/// hub, au même titre que l'IOB.
///
/// `ratioAjuste` est le ratio post-sport **saisi dans le profil** pour ce type
/// d'activité, `nil` s'il n'y en a pas ou si la séance est sortie de la
/// fenêtre d'effet réglée. Quand il existe, c'est lui qui juge la dose
/// (`ValidationRatio`) : la carte sport n'affiche donc plus le chiffre, pour
/// qu'un seul endroit dise quel ratio fait foi.
///
/// Aucun décompte de séances historiques ici : le champ existait, toujours
/// figé à 0, et faisait dire à la carte « basé sur 0 séances » à propos d'un
/// ratio qui venait en réalité du profil. Le mining par type de sport, c'est
/// S1/R2 — pas encore fait, donc rien à afficher.
struct SportDetecte {
    let typeSport: String
    let icone: String
    let ilYAMinutes: Int
    let ratioAjuste: ProfilRatio?
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
/// - **Validation ratio** : dose **de base** du repas (hors ajustements et
///   correction) vs dose issue du ratio configuré en vigueur — celui du sport
///   récent s'il existe, sinon celui du moment de la journée.
/// - **Sport** : présence d'une activité sportive dans les 3h précédant le
///   repas, et ratio post-sport du profil s'il est renseigné — auquel cas
///   c'est lui, et non le ratio du moment, qui juge la dose.
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
    ///   - doseSaisie: dose **de base** du repas (aliments ou dose globale),
    ///     hors ajustements et hors correction — la seule comparable au ratio.
    ///   - glucides: total de glucides du repas (g).
    ///   - ajustements: somme signée des ajustements intentionnels, rapportée
    ///     à part sans jamais entrer dans le verdict.
    ///   - heure: instant de référence (T0 — l'instant de saisie).
    ///   - section: moment du repas, pour choisir le ratio en mode `.parMoment`.
    ///   - contexte: contexte du hub (sport + IOB). `nil` → ces deux blocs absents.
    ///   - analyseRatioObserve: mining R1 déjà calculé (`AnalyseRatioService`),
    ///     transmis par l'appelant — pas de recalcul ici (couche agrégée,
    ///     recalculée sur mutation du hub, pas à chaque frappe de saisie).
    static func contexte(
        doseSaisie: Double,
        glucides: Double,
        ajustements: Double = 0,
        heure: Date,
        section: SectionRepas,
        contexte: ModelContext?,
        analyseRatioObserve: AnalyseRatioObserve = .vide
    ) -> ContexteInsights {
        // Le sport est résolu **avant** la validation : quand une séance
        // récente a un ratio configuré, c'est lui qui fait foi pour juger la
        // dose — le ratio du moment est alors hors sujet. Les deux cartes
        // affichaient auparavant deux ratios contradictoires, celui de la
        // carte sport n'étant utilisé par aucun calcul.
        let sport = sportRecent(avant: heure, contexte: contexte)
        return ContexteInsights(
            validation: validation(
                doseSaisie: doseSaisie, glucides: glucides, ajustements: ajustements,
                section: section, ratioSport: sport?.ratioAjuste,
                analyseRatioObserve: analyseRatioObserve
            ),
            sport: sport,
            iob: iobActif(a: heure, contexte: contexte)
        )
    }

    // MARK: Validation ratio (profil configuré)

    /// - Parameter ratioSport: ratio post-sport en vigueur, quand une séance
    ///   récente en a un de configuré. Prioritaire sur le ratio du moment.
    private static func validation(
        doseSaisie: Double, glucides: Double, ajustements: Double, section: SectionRepas,
        ratioSport: ProfilRatio?,
        analyseRatioObserve: AnalyseRatioObserve
    ) -> ValidationRatio? {
        guard glucides > 0 else { return nil }
        let profil = ProfilService.shared.profil
        let profilRatio: ProfilRatio
        if let ratioSport {
            profilRatio = ratioSport
        } else {
            guard let grammesParUnite = ratioConfigure(section: section, profil: profil), grammesParUnite > 0 else {
                // Ratio non renseigné dans le profil → pas de suggestion possible.
                return nil
            }
            profilRatio = ProfilRatio(
                grammesParUnite: grammesParUnite,
                libelle: section.titre.lowercased()
            )
        }
        let suggeree = glucides / profilRatio.grammesParUnite
        let sectionRecherchee = profil.modeRatio == .unique ? nil : section
        let sectionMining = analyseRatioObserve.sections.first { $0.groupe == sectionRecherchee }

        return ValidationRatio(
            doseSaisie: doseSaisie, doseSuggeree: suggeree, profil: profilRatio,
            ajustements: ajustements, glucides: glucides,
            ratioSportApplique: ratioSport != nil,
            ecartObserve: sectionMining?.ecart, effectifGroupe: sectionMining?.effectif ?? 0
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
            ratioAjuste: ratioSportConfigure(type: activite.type, ilYAMinutes: minutes)
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
            grammesParUnite: grammesParUnite,
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
