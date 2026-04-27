//
//  CarteSection.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct CarteSection: View {
    let icone: String
    let titre: String
    let sousTitre: String
    let couleur: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icone)
                .font(.title2)
                .foregroundStyle(couleur)

            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.headline)
                    .foregroundStyle(couleur)
                Text(sousTitre)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack() {
        CarteSection(
            icone: "circle.fill",
            titre: "CarteSection",
            sousTitre: "Test",
            couleur: .red
        )
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.secondarySystemBackground))
}
