//
//  InsightsService.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import Foundation

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
    let emoji: String
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

/// Source d'insights contextuels affichés dans `RepasSheet`.
///
/// Pour le moment, toutes les valeurs sont **hardcodées et mockées** pour
/// permettre de tester visuellement les différents états :
/// - Les 3 variantes de `ValidationRatio` (cohérente / faible / élevée)
/// - Sport détecté avec et sans ratio ajusté
/// - IOB > 0 avec plusieurs injections actives
///
/// La logique réelle viendra plus tard (corrélation CGM + base de repas + ML).
@Observable
final class InsightsService {

    static let shared = InsightsService()

    // MARK: État réglable

    /// Quelle variante de validation simuler.
    /// Le compositeur peut faire défiler les variantes pour vérifier l'UI.
    var varianteValidationSimulee: VarianteValidation = .faible

    /// Active/désactive le bloc sport simulé.
    var sportSimuleActif: Bool = true

    /// Active/désactive le bloc IOB simulé.
    var iobSimuleActif: Bool = true

    /// Si le sport simulé doit retourner un ratio ajusté ou non.
    var sportAvecRatioAjuste: Bool = false

    /// Profil ratio actif simulé (utilisé partout pour rester cohérent).
    var profilActif: ProfilRatio = ProfilRatio(unitesPour10g: 1.0, libelle: "midi")

    private init() {}

    // MARK: API publique

    /// Calcule la dose suggérée pour un total de glucides en grammes,
    /// en utilisant le profil actif (sans ajustement sport).
    func doseSuggeree(glucides: Double) -> Double {
        (glucides / 10.0) * profilActif.unitesPour10g
    }

    /// Construit le contexte d'insights pour une dose saisie et un total de glucides.
    /// Toutes les branches conditionnelles utilisent les flags réglables ci-dessus.
    func contexte(doseSaisie: Double, glucides: Double) -> ContexteInsights {
        ContexteInsights(
            validation: validationMockee(doseSaisie: doseSaisie, glucides: glucides),
            sport: sportSimuleActif ? sportMocke() : nil,
            iob: iobSimuleActif ? iobMocke() : nil
        )
    }

    // MARK: Variantes simulables

    enum VarianteValidation {
        /// Pas de dose saisie → carte non affichée.
        case absente
        /// Écart < 0.5u → carte verte 1 ligne.
        case coherente
        /// Dose < suggérée de plus de 0.5u → carte orange.
        case faible
        /// Dose > suggérée de plus de 0.5u → carte rouge.
        case elevee
    }

    // MARK: Mocks

    private func validationMockee(doseSaisie: Double, glucides: Double) -> ValidationRatio? {
        let suggeree = doseSuggeree(glucides: glucides)
        switch varianteValidationSimulee {
        case .absente:
            return nil
        case .coherente:
            // On force la dose saisie à coller à la suggérée pour tomber dans l'état cohérent.
            return ValidationRatio(doseSaisie: suggeree, doseSuggeree: suggeree, profil: profilActif)
        case .faible:
            // On simule un cas où l'utilisateur n'a quasi rien saisi.
            return ValidationRatio(doseSaisie: 0, doseSuggeree: suggeree, profil: profilActif)
        case .elevee:
            // On simule une saisie 2u au-dessus de la suggestion.
            return ValidationRatio(doseSaisie: suggeree + 2, doseSuggeree: suggeree, profil: profilActif)
        }
    }

    private func sportMocke() -> SportDetecte {
        if sportAvecRatioAjuste {
            return SportDetecte(
                typeSport: "Yoga",
                emoji: "🧘",
                ilYAMinutes: 60,
                ratioAjuste: ProfilRatio(unitesPour10g: 1.0 / 1.4, libelle: "post-yoga"),
                nombreSeancesHistorique: 8
            )
        } else {
            return SportDetecte(
                typeSport: "Yoga",
                emoji: "🧘",
                ilYAMinutes: 60,
                ratioAjuste: nil,
                nombreSeancesHistorique: 2
            )
        }
    }

    private func iobMocke() -> IOB {
        let maintenant = Date()
        let il30min = maintenant.addingTimeInterval(-30 * 60)
        let il4h30 = maintenant.addingTimeInterval(-4 * 3600 - 30 * 60)
        return IOB(
            unitesTotales: 1.8,
            injections: [
                InjectionActive(unitesInjectees: 2.0, heureInjection: il30min, unitesRestantes: 1.2),
                InjectionActive(unitesInjectees: 1.0, heureInjection: il4h30, unitesRestantes: 0.6),
            ]
        )
    }
}
