//
//  BadgeIOB.swift
//  insulog
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

// MARK: - BadgeIOB
//
// Card de mise en évidence de l'insuline active (IOB — Insulin On
// Board) au démarrage d'un événement (repas ou activité sportive).
//
// Information critique pour un diabétique de type 1 : commencer un
// repas ou une séance avec beaucoup d'insuline rapide encore active
// augmente fortement le risque d'hypoglycémie. La card adapte sa
// couleur (orange / rouge) et son badge de niveau (« Modéré » /
// « Élevé » / « Très élevé ») selon les seuils :
///  - 0 < iob < 1u : orange « Modéré »
///  - 1 ≤ iob < 2u : rouge « Élevé »
///  - iob ≥ 2u    : rouge « Très élevé »
//
// Avant : la même card était dupliquée dans `DetailRepasVue` et
// `DetailActiviteVue` avec leurs propres helpers `couleurIOB` /
// `couleurFondIOB` / `libelleNiveauIOB`. On factorise ici pour qu'une
// évolution des seuils ou du visuel se propage automatiquement.
//
// Conditionnel d'affichage : la card NE doit PAS être présentée si
// l'IOB est nul ou inconnu. Les call-sites passent par
// `BadgeIOB(iob:)?` ou enveloppent le rendu dans un `if let` —
// la struct elle-même reçoit toujours une valeur > 0.
struct BadgeIOB: View {

    /// Insuline active en unités. Doit être strictement positif —
    /// les call-sites filtrent en amont (cf. `BadgeIOB.sectionOptionnelle`).
    let iob: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundStyle(couleurPrincipale)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Insuline active au début")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1fu", iob))
                    .font(.title2.bold())
                    .foregroundStyle(couleurPrincipale)
                    .monospacedDigit()
            }

            Spacer()

            Text(libelleNiveau)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(couleurPrincipale, in: Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(couleurFond)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Insuline active au début : \(String(format: "%.1f", iob)) unités, niveau \(libelleNiveau)"
        )
    }

    // MARK: - Logique des couleurs et libellés

    private var couleurPrincipale: Color {
        switch iob {
        case 0..<1.0:   return .orange
        case 1.0..<2.0: return .red
        default:        return .red
        }
    }

    /// Fond de la card — version diluée (opacity 0.12) de la couleur
    /// principale pour rester lisible sans crier.
    private var couleurFond: Color {
        switch iob {
        case 0..<1.0:   return Color.orange.opacity(0.12)
        default:        return Color.red.opacity(0.12)
        }
    }

    private var libelleNiveau: String {
        switch iob {
        case 0..<1.0:   return "Modéré"
        case 1.0..<2.0: return "Élevé"
        default:        return "Très élevé"
        }
    }
}

// MARK: - Helper de section conditionnelle
//
// Petite fabrique `@ViewBuilder` pour intégrer la card dans un layout
// avec le bon padding latéral, en s'effaçant complètement quand
// l'IOB est `nil` ou nul. Les call-sites évitent ainsi la condition
// `if let iob = ..., iob > 0 { BadgeIOB(...).padding(.horizontal, 16) }`
// dupliquée à chaque appel.
extension BadgeIOB {
    @ViewBuilder
    static func sectionOptionnelle(iob: Double?) -> some View {
        if let iob, iob > 0 {
            BadgeIOB(iob: iob)
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - Aperçu

#Preview("Tous les niveaux") {
    VStack(spacing: 16) {
        BadgeIOB(iob: 0.5)
        BadgeIOB(iob: 1.2)
        BadgeIOB(iob: 2.5)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
