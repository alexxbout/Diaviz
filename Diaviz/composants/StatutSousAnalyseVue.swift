//
//  StatutSousAnalyseVue.swift
//  diaviz
//
//  Created by Alexandre on 30/05/2026.
//

import SwiftUI

/// Rendu compact de l'état d'une sous-analyse du coucher : pill de résultat
/// colorée, compteur de collecte, ou « En attente ».
///
/// Partagé par la carte glance « Analyse du coucher » et les en-têtes des
/// sections pliantes de la page détail, pour garantir une représentation
/// **identique** du statut aux deux endroits (continuité glance → détail).
struct StatutSousAnalyseVue: View {

    let etat: EtatSousAnalyse

    var body: some View {
        switch etat {
        case let .resultat(libelle, ton):
            Text(libelle)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Self.couleur(ton))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Self.couleur(ton).opacity(0.15))
                .clipShape(Capsule(style: .continuous))

        case let .collecte(actuel, requis):
            Label("\(actuel)/\(requis)", systemImage: "hourglass")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

        case .enAttente:
            Text("En attente")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Couleur dérivée du ton du résultat. `static` pour être réutilisable
    /// sans instancier la vue.
    static func couleur(_ ton: TonResultat) -> Color {
        switch ton {
        case .positif:   return .green
        case .attention: return .orange
        case .neutre:    return .secondary
        }
    }
}
