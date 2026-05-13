//
//  LigneMetrique.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Row standard des sections « métriques » dans les pages de détail.
/// Libellé à gauche en `.body`, valeur principale à droite en
/// `.body.bold()` avec chiffres monospaced.
///
/// - `sousValeur` : optionnelle, affichée sous la valeur principale en
///   `.caption` (ex: « À T+1h15 » sous le pic glycémique).
/// - `couleur` : optionnelle, applique une teinte sur la valeur
///   principale (ex: rouge pour une variation glycémique négative).
struct LigneMetrique: View {
    let libelle: String
    let valeur: String
    var sousValeur: String? = nil
    var couleur: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(libelle)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(valeur)
                    .font(.body.bold())
                    .foregroundStyle(couleur ?? .primary)
                    .monospacedDigit()
                if let sousValeur {
                    Text(sousValeur)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(libelle) : \(valeur)\(sousValeur.map { ", \($0)" } ?? "")")
    }
}
