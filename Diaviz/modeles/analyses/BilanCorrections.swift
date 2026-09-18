//
//  BilanCorrections.swift
//  diaviz
//

import Foundation

// MARK: - Tranche de dose (segmentation dose vs résultat)

/// Tranche d'écart entre la dose de correction appliquée et la dose suggérée
/// par le ratio de correction (ISF) configuré — même grammaire que
/// `TrancheRatio` (R1), appliquée ici à l'insuline de correction plutôt qu'au
/// bolus repas.
enum TrancheDoseCorrection: String, Sendable, CaseIterable {
    case doseNettementFaible
    case doseProche
    case doseNettementForte

    var libelle: String {
        switch self {
        case .doseNettementFaible: return "dose nettement plus faible que votre ratio"
        case .doseProche:          return "votre ratio de correction actuel"
        case .doseNettementForte:  return "dose nettement plus élevée que votre ratio"
        }
    }
}

/// Effectif et taux d'adaptation (`issue == .adapte`) d'une tranche de dose —
/// affiché seulement au-delà du garde-fou de volume (voir `CalculBilanCorrections`).
struct BucketDoseCorrection: Sendable, Equatable {
    let tranche: TrancheDoseCorrection
    let total: Int
    let adaptees: Int

    var tauxAdapte: Double { Double(adaptees) / Double(max(1, total)) }
}

// MARK: - Une correction évaluée

/// Une correction rapide (`motif == .correction`), à toute heure — pas
/// limitée à la fenêtre du coucher (≠ `CorrectionSoir`/B3). Observation
/// rétrospective, jamais un conseil de dose.
struct CorrectionEvaluee: Identifiable, Sendable, Equatable {

    let id: UUID
    let date: Date

    /// Glycémie (mg/dL) au moment de la correction.
    let glycemie: Int
    let dose: Double

    /// IOB résiduel au moment de la correction (unités). `nil` si nul.
    let iobAvant: Double?

    /// Pic de glycémie (mg/dL) observé sur la fenêtre de suivi post-correction.
    let picMax: Int

    let issue: IssueCorrection

    /// `true` si `issue == .surCorrection` : la correction a produit une
    /// hypo. Distinct du `VerdictResucrage` (qui juge un resucrage, pas la
    /// correction qui l'a précédé).
    var hypoCausee: Bool { issue == .surCorrection }

    /// IOB au moment précis où la glycémie est passée sous le seuil hypo —
    /// `nil` si `hypoCausee` est faux, ou si la couverture CGM ne permet pas
    /// de dater précisément le passage sous le seuil.
    let iobAuMomentHypo: Double?

    /// `true` si un resucrage correctif pris après cette correction a été
    /// suivi d'une nouvelle hypo dans l'heure (même définition que B1/B3).
    let rechute: Bool

    /// Tranche de dose vs ratio de correction — `nil` si le ratio de
    /// correction n'est pas configuré (dégradation gracieuse : pas de
    /// segmentation sans référence pour la calculer).
    let tranche: TrancheDoseCorrection?
}

// MARK: - Snapshot

/// Snapshot prêt à afficher de la page « Corrections » : bilan de toutes les
/// corrections rapides, à toute heure (≠ B3, limité au coucher).
struct BilanCorrections: Sendable, Equatable {

    /// Triées par date décroissante (la plus récente en tête).
    let corrections: [CorrectionEvaluee]

    /// Segmentation dose vs ratio de correction — vide si le ratio n'est
    /// pas configuré ou si aucune tranche n'atteint le garde-fou de volume.
    let buckets: [BucketDoseCorrection]

    var nombre: Int { corrections.count }
    var nombreAdapte: Int { corrections.count(where: { $0.issue == .adapte }) }
    var nombreInsuffisant: Int { corrections.count(where: { $0.issue == .insuffisant }) }
    var nombreSurCorrection: Int { corrections.count(where: { $0.issue == .surCorrection }) }
    var nombreRechutes: Int { corrections.count(where: \.rechute) }
    var nombreHyposCausees: Int { corrections.count(where: \.hypoCausee) }

    private var iobsConnus: [Double] { corrections.compactMap(\.iobAvant) }
    var iobMoyenAuxCorrections: Double? {
        guard !iobsConnus.isEmpty else { return nil }
        return iobsConnus.reduce(0, +) / Double(iobsConnus.count)
    }
    var iobMaxAuxCorrections: Double? { iobsConnus.max() }

    static var vide: BilanCorrections { .init(corrections: [], buckets: []) }
}
