//
//  IOBCard.swift
//  insulog
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Carte d'IOB (Insulin On Board) — résume l'insuline rapide encore active
/// et liste les injections en cours d'absorption.
///
/// Design aligné sur les autres cartes : icône en cercle indigo à gauche,
/// titre + liste des injections actives à droite.
struct IOBCard: View {

    let iob: IOB

    @State private var afficherExplication: Bool = false

    private let couleurAccent: Color = .indigo

    var body: some View {
        Button {
            afficherExplication = true
        } label: {
            HStack(alignment: .top, spacing: 14) {
                iconeCirculaire
                contenu
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(fondCarte, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $afficherExplication) {
            FeuilleExplicationIOB(iob: iob)
        }
    }

    private var iconeCirculaire: some View {
        ZStack {
            Circle()
                .fill(couleurAccent.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: "drop.fill")
                .font(.title3.bold())
                .foregroundStyle(couleurAccent)
        }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(format(iob.unitesTotales))u d'insuline rapide active")
                .font(.body.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(iob.injections) { injection in
                    Text(ligne(pour: injection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.top, 2)
        }
    }

    private func ligne(pour injection: InjectionActive) -> String {
        let formatHeure = injection.heureInjection.formatted(date: .omitted, time: .shortened)
        return "\(format(injection.unitesInjectees))u à \(formatHeure) → \(format(injection.unitesRestantes))u restantes"
    }

    private func format(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }

    private var fondCarte: LinearGradient {
        LinearGradient(
            colors: [
                couleurAccent.opacity(0.10),
                couleurAccent.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Sheet explicative (placeholder)

private struct FeuilleExplicationIOB: View {
    let iob: IOB
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Total IOB") {
                    Text("\(String(format: "%.1f", iob.unitesTotales))u encore actives")
                        .font(.title3.bold())
                }
                Section("Injections actives") {
                    ForEach(iob.injections) { inj in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(String(format: "%.1f", inj.unitesInjectees))u à \(inj.heureInjection.formatted(date: .omitted, time: .shortened))")
                                .font(.body)
                            Text("Restantes : \(String(format: "%.1f", inj.unitesRestantes))u")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("L'IOB est calculé sur la base d'une courbe d'absorption standard de l'insuline rapide (~4h). Cette courbe sera personnalisée plus tard à partir de ton CGM.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Insuline active")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

#Preview {
    let maintenant = Date()
    let iob = IOB(
        unitesTotales: 1.8,
        injections: [
            InjectionActive(unitesInjectees: 2.0, heureInjection: maintenant.addingTimeInterval(-30 * 60), unitesRestantes: 1.2),
            InjectionActive(unitesInjectees: 1.0, heureInjection: maintenant.addingTimeInterval(-4 * 3600 - 30 * 60), unitesRestantes: 0.6),
        ]
    )
    IOBCard(iob: iob)
        .padding()
        .background(Color(.systemGroupedBackground))
}
