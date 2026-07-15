//
//  BarreSegments3.swift
//  diaviz
//
//  Created by Alexandre on 05/07/2026.
//

import SwiftUI

/// Un segment d'une `BarreSegments3` : une valeur brute (compte ou
/// pourcentage — l'unité importe peu, seul le ratio entre segments compte)
/// et sa couleur.
struct SegmentBarre: Identifiable {
    let id = UUID()
    let couleur: Color
    let valeur: Double
}

/// Barre horizontale à segments proportionnels — langage visuel partagé
/// entre la barre AGP (répartition du temps dans les zones glycémiques,
/// page score) et la barre de répartition des zones de nuit (page analyse
/// du coucher) : mêmes couleurs système (`.green` / `.orange` / `.red`),
/// mêmes proportions, même rendu.
///
/// Largeur de chaque segment proportionnelle à sa `valeur` sur le total.
/// Le pourcentage est rendu en blanc centré, à une taille qui s'adapte à la
/// largeur du segment :
///   - ≥ 15 % → `.caption` bold (largement lisible)
///   - 5–14 % → `.caption2` (compact mais lisible)
///   - < 5 % → pas de texte (sinon illisible), segment rendu en trait fin
///
/// Les coins de la barre sont arrondis via un `clipShape` global — les
/// segments individuels ne sont pas arrondis, c'est le clip qui dessine les
/// arrondis aux extrémités.
struct BarreSegments3: View {

    let segments: [SegmentBarre]
    var hauteur: CGFloat = 32
    var coinArrondi: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.valeur }, 0.0001)
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    SegmentBarreVue(
                        couleur: segment.couleur,
                        pourcent: 100 * segment.valeur / total
                    )
                    .frame(width: geo.size.width * CGFloat(segment.valeur / total))
                }
            }
        }
        .frame(height: hauteur)
        .clipShape(RoundedRectangle(cornerRadius: coinArrondi, style: .continuous))
    }
}

/// Vue d'un segment : remplissage couleur + label « XX % » blanc centré
/// dont la taille de police s'adapte au poids du segment (voir
/// `BarreSegments3` pour les seuils). En deçà de 5 %, pas de texte du tout —
/// un trait fin coloré reste visible grâce à la couleur de fond.
private struct SegmentBarreVue: View {
    let couleur: Color
    let pourcent: Double

    var body: some View {
        ZStack {
            couleur
            if let police = policeTexte {
                Text(String(format: "%.0f %%", pourcent))
                    .font(police)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
    }

    private var policeTexte: Font? {
        switch pourcent {
        case 15...:  return .caption.bold()
        case 5..<15: return .caption2
        default:     return nil
        }
    }
}

// MARK: - Aperçu

#Preview("Barre segments") {
    VStack(spacing: 16) {
        BarreSegments3(segments: [
            SegmentBarre(couleur: .green, valeur: 70),
            SegmentBarre(couleur: .orange, valeur: 20),
            SegmentBarre(couleur: .red, valeur: 10),
        ])
        BarreSegments3(segments: [
            SegmentBarre(couleur: .green, valeur: 2),
            SegmentBarre(couleur: .orange, valeur: 1),
            SegmentBarre(couleur: .red, valeur: 1),
        ])
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
