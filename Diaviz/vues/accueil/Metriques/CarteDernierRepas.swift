//
//  CarteDernierRepas.swift
//  diaviz
//

import SwiftUI

/// Row "Repas" de la liste d'accueil — glucides du dernier repas, nombre
/// d'aliments et temps écoulé, rafraîchi à la minute via `TimelineView`.
struct CarteDernierRepas: View {

    /// Glucides en grammes — affichés à l'entier ("45g", pas "45.0g").
    let glucides: Double

    let depuis: TimeInterval

    /// Emojis des aliments du repas — seul `.count` est utilisé ici (nombre
    /// d'aliments) ; l'emoji lui-même n'est plus affiché dans la row
    /// compacte (cohérence avec les icônes SF Symbols des autres rows).
    let emojis: [String]

    var body: some View {
        let ancre = Date().addingTimeInterval(-depuis)

        TimelineView(.periodic(from: .now, by: 60)) { contexte in
            LigneMetriqueAccueil(
                icone: "fork.knife",
                couleurIcone: couleurIcone,
                couleurFondIcone: couleurIcone.opacity(0.15),
                titre: "Repas",
                sousTitre: sousTitre(maintenant: contexte.date, ancre: ancre)
            ) {
                ValeurMetriqueAccueil(valeur: "\(Int(glucides.rounded()))", unite: "g")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Dernier repas : \(Int(glucides.rounded())) grammes de glucides, \(tempsRelatif(depuis: ancre))"
        )
    }

    private func sousTitre(maintenant: Date, ancre: Date) -> String {
        let temps = tempsRelatif(depuis: ancre, maintenant: maintenant)
        guard !emojis.isEmpty else { return temps }
        let mot = emojis.count == 1 ? "aliment" : "aliments"
        return "\(emojis.count) \(mot) · \(temps)"
    }

    /// Vert foncé "repas" (#639922) — code couleur dédié aux aliments.
    private var couleurIcone: Color {
        Color(red: 0x63 / 255, green: 0x99 / 255, blue: 0x22 / 255)
    }
}

// MARK: - Aperçus

#Preview("Repas - 3 aliments") {
    CarteDernierRepas(glucides: 72, depuis: 4080, emojis: ["🍞", "🧀", "🥛"])
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Repas - Sans détail") {
    CarteDernierRepas(glucides: 45, depuis: 7200, emojis: [])
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}
