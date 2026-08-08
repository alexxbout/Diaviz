//
//  CarteDerniereInjection.swift
//  diaviz
//

import SwiftUI

/// Row "Injection" de la liste d'accueil — dose de la dernière injection,
/// type (rapide/lente) et temps écoulé, rafraîchi à la minute via
/// `TimelineView`.
struct CarteDerniereInjection: View {

    /// `nil` quand le hub ne contient aucune injection — distinct d'une
    /// injection de 0 unité posée à l'instant. Sans cette distinction, une
    /// journée sans aucune injection affichait « 0u à l'instant » comme si
    /// une injection venait d'être saisie.
    let derniere: (dose: Double, depuis: TimeInterval, type: CategorieInjectionAccueil)?

    var body: some View {
        if let derniere {
            let ancre = Date().addingTimeInterval(-derniere.depuis)

            TimelineView(.periodic(from: .now, by: 60)) { contexte in
                LigneMetriqueAccueil(
                    icone: "syringe.fill",
                    couleurIcone: couleurIcone,
                    couleurFondIcone: couleurIcone.opacity(0.15),
                    titre: "Injection \(derniere.type.rawValue.lowercased())",
                    sousTitre: tempsRelatif(depuis: ancre, maintenant: contexte.date)
                ) {
                    ValeurMetriqueAccueil(valeur: doseFormatee(derniere.dose), unite: "u")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Dernière injection : \(doseFormatee(derniere.dose)) unités \(derniere.type.rawValue.lowercased()), \(tempsRelatif(depuis: ancre))"
            )
        } else {
            LigneMetriqueAccueil(
                icone: "syringe.fill",
                couleurIcone: couleurIcone,
                couleurFondIcone: couleurIcone.opacity(0.15),
                titre: "Injection",
                sousTitre: "Aucune aujourd'hui"
            ) {
                EmptyView()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Aucune injection aujourd'hui")
        }
    }

    /// Violet "seringue" (#7F77DD) — code couleur dédié aux injections.
    private var couleurIcone: Color {
        Color(red: 0x7F / 255, green: 0x77 / 255, blue: 0xDD / 255)
    }

    private func doseFormatee(_ dose: Double) -> String {
        let rounded = (dose * 2).rounded() / 2
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }
}

// MARK: - Aperçus

#Preview("Injection - Rapide") {
    CarteDerniereInjection(derniere: (dose: 6.5, depuis: 3900, type: .rapide))
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Injection - Lente") {
    CarteDerniereInjection(derniere: (dose: 18, depuis: 57600, type: .lente))
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Injection - Aucune") {
    CarteDerniereInjection(derniere: nil)
        .surfaceCarte()
        .padding()
        .background(Color(.systemGroupedBackground))
}
