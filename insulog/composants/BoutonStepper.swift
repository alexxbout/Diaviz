//
//  BoutonStepper.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Bouton carré 36×36 utilisé comme "+" ou "−" dans un stepper visuel
/// horizontal. Style `tertiarySystemFill` arrondi à 8 — partagé entre
/// les sheets de saisie de dose (aliments, ajustements, injections)
/// pour un rendu cohérent.
struct BoutonStepper: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.bold())
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
