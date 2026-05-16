//
//  LigneDecompositionGRI.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Row de décomposition GRI

/// Modèle d'une row de la section décomposition.
struct LigneGRI {
    let titre: String
    let description: String
    let pourcent: Double
    let objectifClinique: String
    let couleur: Color
    let icone: String
}

/// Row standard de la section décomposition — icône colorée à gauche,
/// libellé + barre de progression + objectif clinique au milieu,
/// pourcentage + durée à droite.
///
/// `miseEnAvant` active le style « Time in Range » : font légèrement
/// plus appuyée sur les chiffres, padding interne un peu plus généreux.
struct LigneDecompositionGRI: View {

    let ligne: LigneGRI
    var miseEnAvant: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconeColoree

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ligne.titre)
                        .font(miseEnAvant ? .body.weight(.semibold) : .body)
                        .foregroundStyle(.primary)
                    Text(ligne.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                progressionBar

                Text("Objectif : \(ligne.objectifClinique)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPourcent(ligne.pourcent))
                    .font(miseEnAvant
                          ? .body.weight(.bold).monospacedDigit()
                          : .body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(formatDuree(ligne.pourcent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, miseEnAvant ? 10 : 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ligne.titre) \(ligne.description) : \(formatPourcent(ligne.pourcent)), \(formatDuree(ligne.pourcent)). Objectif \(ligne.objectifClinique)"
        )
    }

    private var iconeColoree: some View {
        ZStack {
            Circle()
                .fill(ligne.couleur.opacity(0.18))
            Image(systemName: ligne.icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ligne.couleur)
        }
        .frame(width: 32, height: 32)
    }

    /// Barre de progression horizontale — pleine à 100 % du
    /// `pourcent`. Plafonnée à 100 % de largeur même si la valeur
    /// dépasse l'objectif (cas rare pour le TIR ; jamais pour les
    /// 4 zones hors-cible).
    private var progressionBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(ligne.couleur)
                    .frame(width: geo.size.width * CGFloat(min(1.0, max(0, ligne.pourcent) / 100.0)))
            }
        }
        .frame(height: 6)
    }

    private func formatPourcent(_ valeur: Double) -> String {
        if valeur >= 10 || valeur == floor(valeur) {
            return String(format: "%.0f %%", valeur)
        }
        return String(format: "%.1f %%", valeur)
    }

    /// Convertit un pourcentage de journée en durée lisible :
    ///   - < 60 min → "12 min"
    ///   - ≥ 60 min → "4h19" (sans espace, format compact)
    private func formatDuree(_ pourcent: Double) -> String {
        let totalSec = ScoreJournalier.duree(pourPourcent: pourcent)
        let totalMin = Int(totalSec / 60)
        if totalMin < 60 {
            return "\(totalMin) min"
        }
        let h = totalMin / 60
        let m = totalMin % 60
        if m == 0 { return "\(h) h" }
        return String(format: "%dh%02d", h, m)
    }
}
