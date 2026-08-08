//
//  CarteDerniereInjection.swift
//  diaviz
//

import SwiftUI

/// Row "Injection" de la liste d'accueil — dose de la dernière injection,
/// type (rapide/lente) et temps écoulé, rafraîchi à la minute via
/// `TimelineView`.
struct CarteDerniereInjection: View {

    let dose: Double
    let depuis: TimeInterval
    let type: CategorieInjectionAccueil

    var body: some View {
        let ancre = Date().addingTimeInterval(-depuis)

        TimelineView(.periodic(from: .now, by: 60)) { contexte in
            LigneMetriqueAccueil(
                icone: "syringe.fill",
                couleurIcone: couleurIcone,
                couleurFondIcone: couleurIcone.opacity(0.15),
                titre: "Injection \(type.rawValue.lowercased())",
                sousTitre: tempsRelatif(depuis: ancre, maintenant: contexte.date)
            ) {
                ValeurMetriqueAccueil(valeur: doseFormatee, unite: "u")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Dernière injection : \(doseFormatee) unités \(type.rawValue.lowercased()), \(tempsRelatif(depuis: ancre))"
        )
    }

    /// Violet "seringue" (#7F77DD) — code couleur dédié aux injections.
    private var couleurIcone: Color {
        Color(red: 0x7F / 255, green: 0x77 / 255, blue: 0xDD / 255)
    }

    private var doseFormatee: String {
        let rounded = (dose * 2).rounded() / 2
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }
}

// MARK: - Aperçus

#Preview("Injection - Rapide") {
    CarteDerniereInjection(dose: 6.5, depuis: 3900, type: .rapide)
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Injection - Lente") {
    CarteDerniereInjection(dose: 18, depuis: 57600, type: .lente)
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}
