//
//  CarteIOB.swift
//  diaviz
//

import SwiftUI

/// Row "Insuline active" (IOB — Insulin On Board) de la liste d'accueil.
///
/// La valeur reste en couleur primaire — pas de code couleur par palier :
/// l'IOB élevé n'est pas une alerte en soi. Le rouge reste réservé aux
/// vrais signaux d'alerte (cf. `CarteHypos`).
struct CarteIOB: View {

    /// IOB en unités. Peut être nul ou très faible.
    let valeur: Double

    /// Courbe d'IOB — conservée pour compat d'API mais plus affichée dans
    /// le layout liste (la mini-courbe de décroissance encombrait plus
    /// qu'elle n'informait à cette échelle ; le sous-libellé "dans Xh"
    /// donne l'info utile en un mot).
    let pointsIOB: [PointIOB]

    private var actif: Bool {
        valeur >= 0.05 && !pointsIOB.isEmpty
    }

    var body: some View {
        LigneMetriqueAccueil(
            icone: "drop.fill",
            couleurIcone: couleurIcone,
            couleurFondIcone: couleurIcone.opacity(0.15),
            titre: "Insuline active",
            sousTitre: actif ? "Reste actif \(formatDuree(minutesJusquAFin))" : "Aucune insuline active"
        ) {
            ValeurMetriqueAccueil(valeur: valeurFormatee, unite: "u")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Insuline active : \(valeurFormatee) unités")
    }

    private var minutesJusquAFin: Int {
        pointsIOB.last?.minutesDepuisMaintenant ?? 0
    }

    private func formatDuree(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 { return "\(h)h" }
        return "\(h)h\(String(format: "%02d", m))"
    }

    /// Bleu "insuline" (#378ADD), constant indépendamment du niveau.
    private var couleurIcone: Color {
        Color(red: 0x37 / 255, green: 0x8A / 255, blue: 0xDD / 255)
    }

    private var valeurFormatee: String {
        String(format: "%.1f", valeur)
    }
}

// MARK: - Aperçus

#Preview("IOB - 3.2u actif") {
    CarteIOB(
        valeur: MetriquesAccueil.mockNormal.iob,
        pointsIOB: MetriquesAccueil.mockNormal.pointsIOB
    )
    .surfaceCarte()
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("IOB - 0u inactif") {
    CarteIOB(valeur: 0, pointsIOB: [])
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}
