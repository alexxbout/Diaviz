//
//  CarteVerdictBasale.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Carte 1 — **constat** basale, piloté par `BasalVerdict`. Trois
/// rendus distincts selon l'état :
///
///   - `.sufficient` — verdict formel basé sur la tendance détectée
///     (descendante / ascendante / stable), avec pente moyenne et
///     volume de nuits analysées.
///   - `.recentChange` — pas encore assez de nuits depuis le dernier
///     changement de dose (1-2 sur 3 nécessaires). Affiche une barre
///     de progression.
///   - `.noData` — aucune nuit valide. Carte minimaliste « En attente
///     de données ».
///
/// Le composant consomme directement `AnalyseBasaleDetail.basalVerdict`
/// — le calcul des seuils et de la tendance vit côté service.
struct CarteVerdictBasale: View {

    let verdict: BasalVerdict

    /// Wrapper d'initialisation depuis `AnalyseBasaleDetail` — pratique
    /// pour le câblage depuis `DetailAnalyseBasaleVue`.
    init(analyse: AnalyseBasaleDetail) {
        self.verdict = analyse.basalVerdict
    }

    init(verdict: BasalVerdict) {
        self.verdict = verdict
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch verdict.state {
            case .sufficient:    contenuSufficient
            case .recentChange:  contenuRecentChange
            case .noData:        contenuNoData
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - État 1 : verdict possible

    private var contenuSufficient: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconeConstat)
                    .font(.title3)
                    .foregroundStyle(couleurConstat)
                    .accessibilityHidden(true)
                Text(libelleConstat)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(couleurConstat)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            // Hypos nocturnes : signal prioritaire, mis en avant si présent.
            if verdict.hypoCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                    Text("\(verdict.hypoCount) hypo\(verdict.hypoCount > 1 ? "s" : "") nocturne\(verdict.hypoCount > 1 ? "s" : "")")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(verdict.hypoCount) hypoglycémies nocturnes")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Dérive moy. : \(libelleDerive)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Image(systemName: iconeFlechePente)
                        .font(.system(size: 14))
                        .foregroundStyle(couleurFlechePente)
                        .accessibilityHidden(true)
                }

                Text("\(verdict.validNights) nuits analysées · \(verdict.excludedNights) exclues sur \(verdict.totalNights) jours")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text("Dose actuelle : \(libelleDose(verdict.currentDose))u")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - État 2 : nouvelle dose en observation

    private var contenuRecentChange: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.title3)
                    .accessibilityHidden(true)
                Text("Nouvelle dose en observation")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                Text(libelleDoseAvecDate)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text(libelleProgression)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                BarreProgressionFine(
                    value: Double(verdict.validNights),
                    total: 3
                )
                .padding(.top, 4)
            }
        }
    }

    // MARK: - État 3 : aucune donnée

    private var contenuNoData: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.title3)
                    .accessibilityHidden(true)
                Text("En attente de données")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                Text("Dose actuelle : \(libelleDose(verdict.currentDose))u")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Aucune nuit analysée")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Constat (override « en amélioration »)

    /// L'état « en amélioration » prime sur la tendance brute : la situation
    /// penchait « à revoir » mais les nuits récentes sont redevenues stables.
    private var iconeConstat: String { verdict.enAmelioration ? "checkmark.circle.fill" : iconeTendance }
    private var libelleConstat: String { verdict.enAmelioration ? "En amélioration" : libelleTendance }
    private var couleurConstat: Color { verdict.enAmelioration ? .green : couleurTendance }

    // MARK: - Dérivés tendance

    private var iconeTendance: String {
        switch verdict.trend {
        case .descending, .ascending:  return "exclamationmark.triangle.fill"
        case .stable:                  return "checkmark.circle.fill"
        case .none:                    return "hourglass"
        }
    }

    private var libelleTendance: String {
        switch verdict.trend {
        case .descending:  return "Tendance descendante"
        case .ascending:   return "Tendance ascendante"
        case .stable:      return "Tendance stable"
        case .none:        return ""
        }
    }

    private var couleurTendance: Color {
        switch verdict.trend {
        case .descending, .ascending:  return .orange
        case .stable:                  return .green
        case .none:                    return .primary
        }
    }

    // MARK: - Dérivés flèche pente

    private var iconeFlechePente: String {
        switch verdict.trend {
        case .descending:  return "arrow.down.right"
        case .ascending:   return "arrow.up.right"
        case .stable:      return "arrow.right"
        case .none:        return "arrow.right"
        }
    }

    /// Code couleur : ambre quand on descend (signal d'attention sur
    /// une basale potentiellement trop élevée), rouge quand on monte
    /// (basale potentiellement trop faible), vert quand on est stable.
    private var couleurFlechePente: Color {
        switch verdict.trend {
        case .descending:  return Color(red: 186/255, green: 117/255, blue: 23/255) // ambre
        case .ascending:   return .red
        case .stable:      return .green
        case .none:        return .secondary
        }
    }

    // MARK: - Formatage

    /// Dérive moyenne par nuit — l'unité de décision (comparable au seuil
    /// ±30 mg/dL), pas la pente horaire qui ne parle à personne.
    private var libelleDerive: String {
        guard let d = verdict.derive else { return "—" }
        return String(format: "%+d", Int(d.rounded())) + " mg/dL / nuit"
    }

    private func libelleDose(_ d: Double) -> String {
        d == floor(d) ? String(format: "%.0f", d) : String(format: "%.1f", d)
    }

    /// « Dose actuelle : 17u (depuis le 15 mai) ».
    private var libelleDoseAvecDate: String {
        let dose = "Dose actuelle : \(libelleDose(verdict.currentDose))u"
        guard let date = verdict.doseChangedDate else { return dose }
        return "\(dose) (depuis le \(libelleDateCourte(date)))"
    }

    private func libelleDateCourte(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
    }

    /// « 2 nuits analysées · encore 1 nuit nécessaire ».
    private var libelleProgression: String {
        let n = verdict.validNights
        let manquant = verdict.nightsNeeded
        let nuitsLib = manquant == 1 ? "1 nuit nécessaire" : "\(manquant) nuits nécessaires"
        return "\(n) nuits analysées · encore \(nuitsLib)"
    }
}

// MARK: - Barre de progression fine

/// Barre 4 pt de haut, coins arrondis 2 pt — sans label, le texte
/// au-dessus suffit (cf. spec « Pas de label sur la barre »).
private struct BarreProgressionFine: View {

    let value: Double
    let total: Double

    private var progression: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progression)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progression \(Int(value)) sur \(Int(total)) nuits")
    }
}

// MARK: - Aperçus

#Preview("Verdict - Sufficient (trop élevée)") {
    CarteVerdictBasale(analyse: .mockStandard14j)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Verdict - Sufficient (adaptée)") {
    CarteVerdictBasale(analyse: .mockAdaptee)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Verdict - Recent change") {
    CarteVerdictBasale(analyse: .mockRecentChange)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Verdict - No data") {
    CarteVerdictBasale(analyse: .mockNoData)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
