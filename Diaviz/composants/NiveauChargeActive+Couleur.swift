//
//  NiveauChargeActive+Couleur.swift
//  diaviz
//

import SwiftUI

extension NiveauChargeActive {
    /// Couleur du niveau de charge active — source unique pour tous les
    /// usages (page Charge et glycémie, badges repas et nuit, pastilles des
    /// soirs B2/B3). Normale = neutre : rien à signaler.
    var couleur: Color {
        switch self {
        case .basse:   .red
        case .normale: .secondary
        case .haute:   .blue
        }
    }
}

extension SyntheseChargeActive {
    /// « Charge active haute depuis 4 j » — `nil` quand il n'y a rien à
    /// signaler (niveau normal) ou pas de niveau (pas assez de recul).
    var libelleHorsNormale: String? {
        guard case let .disponible(_, niveau, depuisJours) = etat, niveau != .normale else { return nil }
        guard let depuisJours else { return niveau.libelle }
        return "\(niveau.libelle) depuis \(depuisJours) j"
    }
}

/// Ligne « flamme + niveau » affichée sous un verdict (nuit B1) quand la
/// charge active sort de la normale — contexte corrélé, jamais une cause.
struct LigneChargeHorsNormale: View {

    let synthese: SyntheseChargeActive?

    var body: some View {
        if let synthese, let libelle = synthese.libelleHorsNormale, let niveau = synthese.niveau {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.caption2.weight(.semibold))
                Text(libelle)
                    .font(.caption)
            }
            .foregroundStyle(niveau.couleur)
            .accessibilityElement(children: .combine)
        }
    }
}
