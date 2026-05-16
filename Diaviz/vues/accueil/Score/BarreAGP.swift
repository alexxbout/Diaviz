//
//  BarreAGP.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Barre AGP segmentée

/// Barre horizontale segmentée pleine largeur — résume la répartition
/// du temps sur 24 h dans **3 zones glycémiques agrégées** :
///
///   - Hypo (rouge #E24B4A) — somme `tbrLevel2 + tbrLevel1` (< 70 mg/dL)
///   - En cible (vert #1D9E75) — `tir` (70–180 mg/dL)
///   - Hyper (orange #EF9F27) — somme `tarLevel1 + tarLevel2` (> 180 mg/dL)
///
/// Le détail à 5 zones (sévère / non-sévère) reste consultable dans
/// la section DÉCOMPOSITION juste en dessous — ici on agrège pour un
/// résumé lisible d'un coup d'œil.
///
/// Largeur de chaque segment proportionnelle à son pourcentage. Le
/// pourcentage est rendu en blanc centré dans le segment, à une taille
/// qui s'adapte à la largeur disponible :
///   - ≥ 15 % → `.caption` bold (largement lisible)
///   - 5–14 % → `.caption2` (compact mais lisible)
///   - < 5 % → pas de texte (sinon illisible), segment rendu en trait fin
///
/// Les coins de la barre sont arrondis via un `clipShape` global
/// (8 pt) — les segments individuels ne sont pas arrondis, c'est le
/// clip qui dessine les arrondis aux extrémités.
struct BarreAGP: View {

    let faits: FaitsJour

    private static let hauteur: CGFloat = 32
    private static let coinArrondi: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let segments = construireSegments(largeurTotale: geo.size.width)
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { (_, seg) in
                    SegmentAGPVue(segment: seg)
                }
            }
        }
        .frame(height: Self.hauteur)
        .clipShape(RoundedRectangle(cornerRadius: Self.coinArrondi, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(libelleAccessibilite)
    }

    /// Construit les 3 segments agrégés (hypo / cible / hyper) en
    /// répartissant la largeur disponible au prorata des pourcentages.
    ///
    /// Normalisation par la somme réelle plutôt que par 100 fixe : si
    /// le mock totalise 99.5 (à cause des arrondis de génération), la
    /// barre remplit quand même toute la largeur — sans cette
    /// normalisation un mince espace blanc apparaîtrait à droite.
    private func construireSegments(largeurTotale: CGFloat) -> [SegmentAGP] {
        let pctHypo = faits.tbrLevel2 + faits.tbrLevel1
        let pctCible = faits.tir
        let pctHyper = faits.tarLevel1 + faits.tarLevel2

        let total = pctHypo + pctCible + pctHyper
        let denominateur = max(total, 0.0001) // anti-div0 sur cas dégénéré
        func largeur(_ pct: Double) -> CGFloat {
            largeurTotale * CGFloat(pct / denominateur)
        }

        // Couleurs système iOS — alignées sur celles utilisées par la
        // section DÉCOMPOSITION juste en dessous (`.red` pour la row
        // Hypo, `.green` pour Temps en cible, `.orange` pour Hyper).
        // Apple les a calibrées pour fonctionner ensemble : même
        // niveau de vivacité, accessibilité Dynamic Color (mode clair
        // / sombre, contraste élevé) gérée automatiquement.
        return [
            SegmentAGP(
                pourcent: pctHypo,
                couleur: .red,
                largeur: largeur(pctHypo),
                titre: "Hypo"
            ),
            SegmentAGP(
                pourcent: pctCible,
                couleur: .green,
                largeur: largeur(pctCible),
                titre: "En cible"
            ),
            SegmentAGP(
                pourcent: pctHyper,
                couleur: .orange,
                largeur: largeur(pctHyper),
                titre: "Hyper"
            ),
        ]
    }

    private var libelleAccessibilite: String {
        let pctHypo = faits.tbrLevel2 + faits.tbrLevel1
        let pctHyper = faits.tarLevel1 + faits.tarLevel2
        let lignes: [(String, Double)] = [
            ("Hypo", pctHypo),
            ("En cible", faits.tir),
            ("Hyper", pctHyper),
        ]
        return lignes
            .map { String(format: "%@ %.0f pour cent", $0.0, $0.1) }
            .joined(separator: ", ")
    }
}

/// Modèle interne d'un segment de la barre AGP.
private struct SegmentAGP {
    let pourcent: Double
    let couleur: Color
    let largeur: CGFloat
    let titre: String
}

/// Vue d'un segment : remplissage couleur + label « XX % » blanc centré
/// dont la taille de police s'adapte au poids du segment (voir
/// `BarreAGP` pour les seuils). En deçà de 5 %, pas de texte du tout —
/// un trait fin coloré reste visible grâce à la couleur de fond.
private struct SegmentAGPVue: View {
    let segment: SegmentAGP

    var body: some View {
        ZStack {
            segment.couleur
            if let police = policeTexte {
                Text(String(format: "%.0f %%", segment.pourcent))
                    .font(police)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
        .frame(width: max(0, segment.largeur))
    }

    /// Mapping pourcentage → font, ou `nil` si le segment est trop
    /// petit pour rendre du texte lisible. Calé sur les seuils
    /// spec'd : ≥ 15 → caption bold, 5–14 → caption2, < 5 → rien.
    private var policeTexte: Font? {
        switch segment.pourcent {
        case 15...:        return .caption.bold()
        case 5..<15:       return .caption2
        default:           return nil
        }
    }
}
