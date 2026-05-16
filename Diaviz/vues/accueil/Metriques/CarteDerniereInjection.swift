//
//  CarteDerniereInjection.swift
//  diaviz
//
//  Created by Alexandre on 14/05/2026.
//

import SwiftUI

/// Carte "Injection" — troisième carte de la grille d'accueil.
/// Présente la dose en unités de la dernière injection, le temps
/// écoulé depuis (rafraîchi à la minute via `TimelineView`) et un
/// **badge pill** indiquant le type — orange pour une rapide
/// (bolus repas ou correction), bleu pour une lente (basale longue
/// action).
///
/// Le temps écoulé est ancré à `Date() - depuis` à l'apparition de
/// la vue, puis recalculé périodiquement contre `now` — l'écart
/// glisse sans dériver tant que la vue vit.
struct CarteDerniereInjection: View {

    /// Dose en unités. Format affiché à la décimale près si nécessaire
    /// (3.5u, 4u, 12u — pas 4.0u).
    let dose: Double

    /// Temps écoulé en secondes depuis l'injection. Sert de base au
    /// rafraîchissement périodique : on convertit `now - depuis` à
    /// chaque tick d'horloge.
    let depuis: TimeInterval

    /// Catégorie d'insuline — pilote la couleur du badge en bas de
    /// carte (orange pour rapide, bleu pour lente).
    let type: CategorieInjectionAccueil

    var body: some View {
        // Référence temporelle figée à l'instant où la vue apparaît —
        // c'est la "date de l'injection" reconstituée à rebours. Tant
        // que la vue vit, `TimelineView` rafraîchit `il y a Xh Ym` à
        // partir de cette ancre, sans dériver.
        let ancre = Date().addingTimeInterval(-depuis)

        CarteMetriqueShell {
            // VStack spacing 0 + paddings explicites — voir la note
            // sur l'alignement des valeurs dans `CarteHypos`.
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Ligne icône + titre (haut)
                HStack(spacing: 4) {
                    Image(systemName: "syringe.fill")
                        .font(.footnote)
                        .foregroundStyle(couleurIcone)
                        .accessibilityHidden(true)
                    Text("Injection")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                // MARK: Valeur principale + unité collée (Y fixe)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(doseFormatee)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("u")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .padding(.top, 24)

                Spacer(minLength: 0)

                // MARK: Bloc bas — temps relatif + badge type, ancrés
                // au bas de la carte.
                VStack(alignment: .leading, spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 60)) { contexte in
                        Text(tempsRelatif(depuis: ancre, maintenant: contexte.date))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Text(type.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(couleurBadge, in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Dernière injection : \(doseFormatee) unités \(type.rawValue.lowercased()), \(tempsRelatif(depuis: ancre))"
        )
    }

    // MARK: - Apparence

    /// Violet "seringue" (#7F77DD) — code couleur dédié aux injections
    /// dans la charte, distinct du bleu "insuline active".
    private var couleurIcone: Color {
        Color(red: 0x7F / 255, green: 0x77 / 255, blue: 0xDD / 255)
    }

    /// Orange pour rapide (bolus = action urgente), bleu pour lente
    /// (basale = action de fond) — convention héritée de la charte de
    /// l'app, distinct du bleu plus saturé "insuline active" (#378ADD).
    private var couleurBadge: Color {
        type == .lente ? .blue : .orange
    }

    // MARK: - Formatage

    /// Affiche un entier sans décimale ("4u", "12u"), une demi sinon
    /// ("3.5u"). Évite "4.0u" pour les doses rondes — c'est plus
    /// lisible et fidèle à la façon dont le diabétique lit son stylo
    /// (clics par demi-unité).
    private var doseFormatee: String {
        let rounded = (dose * 2).rounded() / 2 // arrondi à la demi-unité
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

}

// MARK: - Aperçus

#Preview("Injection - Rapide") {
    CarteDerniereInjection(dose: 6.5, depuis: 3900, type: .rapide)
        .frame(width: 170, height: 180)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Injection - Lente") {
    CarteDerniereInjection(dose: 18, depuis: 57600, type: .lente)
        .frame(width: 170, height: 180)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Injection - 3.5u récente") {
    CarteDerniereInjection(dose: 3.5, depuis: 600, type: .rapide)
        .frame(width: 170, height: 180)
        .padding()
        .background(Color(.systemGroupedBackground))
}
