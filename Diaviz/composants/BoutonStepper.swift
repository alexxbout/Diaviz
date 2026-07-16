//
//  BoutonStepper.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Bouton carré 36×36 utilisé comme "+" ou "−" dans un stepper visuel
/// horizontal. Style `tertiarySystemFill` arrondi à 8 — partagé entre
/// les sheets de saisie de dose (aliments, ajustements, injections)
/// pour un rendu cohérent.
///
/// Retour haptique `.increase`/`.decrease` inféré du symbole ("plus"/"minus")
/// — composant partagé, donc un seul endroit à maintenir pour que tous les
/// steppers de dose de l'app (lente, correction, aliment, ajustement) aient
/// le même feedback tactile.
struct BoutonStepper: View {
    let systemImage: String
    let action: () -> Void

    @State private var declenche = false

    var body: some View {
        Button {
            declenche.toggle()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.body.bold())
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(systemImage == "plus" ? .increase : .decrease, trigger: declenche)
    }
}

#Preview {
    HStack {
        BoutonStepper(systemImage: "minus") {}
        Spacer()
        Text("4.5u")
            .font(.title2.bold())
            .monospacedDigit()
        Spacer()
        BoutonStepper(systemImage: "plus") {}
    }
    .padding()
}
