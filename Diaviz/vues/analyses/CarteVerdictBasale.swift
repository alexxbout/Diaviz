//
//  CarteVerdictBasale.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

/// Carte 1 — verdict synthétique de l'analyse basale, pente moyenne,
/// contexte « nuits valides / exclues » et dose actuelle.
///
/// La carte ne propose plus de picker 7/14/30 jours : l'analyse
/// travaille toujours sur la **fenêtre clinique standard de 14 nuits**
/// glissantes (cf. `kFenetreNuits`). Les nuits valides et leur raison
/// d'exclusion sont visualisées par la `TimelineNuitsVue` juste en
/// dessous.
struct CarteVerdictBasale: View {

    let analyse: AnalyseBasaleDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            verdictPrincipal
            ligneTendance
            contexte
            doseActuelle
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Verdict principal

    private var verdictPrincipal: some View {
        HStack(spacing: 8) {
            Image(systemName: iconeVerdict)
                .font(.title3)
                .foregroundStyle(couleurVerdict)
                .accessibilityHidden(true)

            Text(libelleVerdict)
                .font(.title3.bold())
                .foregroundStyle(couleurVerdict)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Ligne 2 — pente moyenne + flèche

    private var ligneTendance: some View {
        HStack(spacing: 6) {
            Text("Pente moy. : \(libellePente) mg/dL/h")
                .font(.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Image(systemName: iconeFleche)
                .font(.body)
                .foregroundStyle(couleurFleche)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Contexte (avec ou sans changement de dose récent)

    /// Deux variantes selon `changementDoseRecent` :
    ///   - Aucun changement → une seule ligne « N valides · M exclues sur 14 jours »
    ///   - Changement récent → deux lignes « Depuis le changement de dose » +
    ///     « N analysées · M exclues »
    @ViewBuilder
    private var contexte: some View {
        if let dateChangement = analyse.changementDoseRecent {
            VStack(alignment: .leading, spacing: 2) {
                Text("Depuis le changement de dose \(libelleDepuis(dateChangement))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(analyse.nuitsAnalysees) nuits analysées · \(analyse.nuitsExclues) exclues")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("\(analyse.nuitsAnalysees) nuits valides · \(analyse.nuitsExclues) exclues sur \(kFenetreNuits) jours")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dose actuelle

    private var doseActuelle: some View {
        Text("Dose actuelle : \(libelleDose)u")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
    }

    // MARK: - Dérivés du verdict

    private var iconeVerdict: String {
        switch analyse.verdict {
        case .adaptee:                return "checkmark.circle.fill"
        case .tropHaute, .tropBasse:  return "exclamationmark.triangle.fill"
        case .donneesInsuffisantes:   return "clock.fill"
        }
    }

    private var libelleVerdict: String {
        switch analyse.verdict {
        case .adaptee:                return "Basale adaptée"
        case .tropHaute:              return "Basale potentiellement trop élevée"
        case .tropBasse:              return "Basale potentiellement trop basse"
        case .donneesInsuffisantes:   return "Données insuffisantes"
        }
    }

    private var couleurVerdict: Color {
        switch analyse.verdict {
        case .adaptee:                return .green
        case .tropHaute, .tropBasse:  return .orange
        case .donneesInsuffisantes:   return .secondary
        }
    }

    // MARK: - Flèche de pente

    /// `< -0.3` = descente nette, `> +0.3` = montée nette, sinon stable.
    /// Seuils volontairement étroits — au-delà de ±0.3 mg/dL/h sur 6h
    /// le glucose dérive d'environ 10 mg/dL, ce qui mérite un signal.
    private var iconeFleche: String {
        switch analyse.penteMoyenne {
        case ..<(-0.3):  return "arrow.down.right"
        case 0.3...:     return "arrow.up.right"
        default:         return "arrow.right"
        }
    }

    private var couleurFleche: Color {
        switch analyse.penteMoyenne {
        case ..<(-0.3), 0.3...:  return .orange
        default:                 return .green
        }
    }

    // MARK: - Formatage

    /// Pente signée avec 1 décimale (« -2.1 », « +0.0 », « +1.8 »).
    private var libellePente: String {
        let signe = analyse.penteMoyenne >= 0 ? "+" : ""
        return signe + String(format: "%.1f", analyse.penteMoyenne)
    }

    /// « 18 » pour les entiers, « 18.5 » sinon — aligné sur le format
    /// utilisé par les sheets d'enregistrement de lente.
    private var libelleDose: String {
        analyse.doseActuelle == floor(analyse.doseActuelle)
            ? String(format: "%.0f", analyse.doseActuelle)
            : String(format: "%.1f", analyse.doseActuelle)
    }

    /// Formatage relatif court pour la date de changement de dose :
    /// « hier », « depuis mardi » (< 7 jours), « depuis le 3 mai »
    /// (> 7 jours). Locale forcée à fr_FR pour rester stable.
    private func libelleDepuis(_ date: Date) -> String {
        let now = Date.now
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case 0:        return "aujourd'hui"
        case 1:        return "hier"
        case 2..<7:
            let jour = date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR")))
            return "\(jour) (il y a \(days) jours)"
        default:
            let lib = date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
            return "le \(lib)"
        }
    }
}

// MARK: - Aperçus

#Preview("Verdict - Standard 14j") {
    CarteVerdictBasale(analyse: .mockStandard14j)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Verdict - Changement de dose") {
    CarteVerdictBasale(analyse: .mockChangementDose)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Verdict - Adaptée") {
    CarteVerdictBasale(analyse: .mockAdaptee)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Verdict - Données insuffisantes") {
    CarteVerdictBasale(analyse: .mockInsuffisant)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}
