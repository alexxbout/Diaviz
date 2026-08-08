//
//  CarteDernierRepas.swift
//  diaviz
//

import SwiftUI

/// Row "Repas" de la liste d'accueil — glucides du dernier repas, nombre
/// d'aliments et temps écoulé, rafraîchi à la minute via `TimelineView`.
struct CarteDernierRepas: View {

    /// `nil` quand le hub ne contient aucun repas — distinct d'un repas de
    /// 0g posé à l'instant. Sans cette distinction, une journée sans aucun
    /// repas affichait « 0g à l'instant » comme si un repas venait d'être
    /// saisi.
    let dernier: (glucides: Double, depuis: TimeInterval, emojis: [String])?

    var body: some View {
        if let dernier {
            let ancre = Date().addingTimeInterval(-dernier.depuis)

            TimelineView(.periodic(from: .now, by: 60)) { contexte in
                LigneMetriqueAccueil(
                    icone: "fork.knife",
                    couleurIcone: couleurIcone,
                    couleurFondIcone: couleurIcone.opacity(0.15),
                    titre: "Repas",
                    sousTitre: sousTitre(maintenant: contexte.date, ancre: ancre, emojis: dernier.emojis)
                ) {
                    ValeurMetriqueAccueil(valeur: "\(Int(dernier.glucides.rounded()))", unite: "g")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Dernier repas : \(Int(dernier.glucides.rounded())) grammes de glucides, \(tempsRelatif(depuis: ancre))"
            )
        } else {
            LigneMetriqueAccueil(
                icone: "fork.knife",
                couleurIcone: couleurIcone,
                couleurFondIcone: couleurIcone.opacity(0.15),
                titre: "Repas",
                sousTitre: "Aucun aujourd'hui"
            ) {
                EmptyView()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Aucun repas aujourd'hui")
        }
    }

    private func sousTitre(maintenant: Date, ancre: Date, emojis: [String]) -> String {
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
    CarteDernierRepas(dernier: (glucides: 72, depuis: 4080, emojis: ["🍞", "🧀", "🥛"]))
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Repas - Sans détail") {
    CarteDernierRepas(dernier: (glucides: 45, depuis: 7200, emojis: []))
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Repas - Aucun") {
    CarteDernierRepas(dernier: nil)
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}
