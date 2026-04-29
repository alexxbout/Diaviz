//
//  SportDetecteCard.swift
//  insulog
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Carte affichée quand un sport a été détecté dans la fenêtre récente.
/// Indique si on a un ratio ajusté disponible (basé sur l'historique) ou
/// si on n'a pas encore assez de données.
///
/// Design aligné sur les autres cartes : icône en cercle bleu à gauche,
/// titre + ratio ajusté + détail à droite, gradient subtil et ombre.
struct SportDetecteCard: View {

    let sport: SportDetecte

    @State private var afficherExplication: Bool = false

    private let couleurAccent: Color = .blue

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
            FeuilleExplicationSport(sport: sport)
        }
    }

    private var iconeCirculaire: some View {
        ZStack {
            Circle()
                .fill(couleurAccent.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: "bolt.fill")
                .font(.title3.bold())
                .foregroundStyle(couleurAccent)
        }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(sport.emoji) \(sport.typeSport) détecté il y a \(libelleTemps)")
                .font(.body.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            if let ratio = sport.ratioAjuste {
                badgeRatioAjuste(ratio: ratio)
            }

            Text(messageContextuel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func badgeRatioAjuste(ratio: ProfilRatio) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
                .font(.caption2.bold())
            Text("Ratio ajusté \(ratio.description)")
                .font(.caption.bold())
        }
        .foregroundStyle(couleurAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(couleurAccent.opacity(0.14), in: Capsule())
    }

    private var libelleTemps: String {
        let m = sport.ilYAMinutes
        if m < 60 { return "\(m)min" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h\(r)"
    }

    private var messageContextuel: String {
        if sport.ratioAjuste != nil {
            return "Basé sur \(sport.nombreSeancesHistorique) séances post-\(sport.typeSport.lowercased())"
        } else {
            return "Pas assez de données post-\(sport.typeSport.lowercased()) pour ajuster le ratio"
        }
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

private struct FeuilleExplicationSport: View {
    let sport: SportDetecte
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Activité détectée") {
                    LabeledContent("Type", value: "\(sport.emoji) \(sport.typeSport)")
                    LabeledContent("Il y a", value: "\(sport.ilYAMinutes) min")
                    LabeledContent("Historique", value: "\(sport.nombreSeancesHistorique) séances")
                }
                if let ratio = sport.ratioAjuste {
                    Section("Ratio ajusté") {
                        Text(ratio.description)
                    }
                }
                Section {
                    Text("Le sport peut modifier la sensibilité à l'insuline pendant plusieurs heures. Insulog observe cet effet sur ton historique pour proposer un ratio plus juste après chaque type d'activité.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sport détecté")
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
    let avec = SportDetecte(
        typeSport: "Yoga", emoji: "🧘", ilYAMinutes: 60,
        ratioAjuste: ProfilRatio(unitesPour10g: 1.0 / 1.4, libelle: "post-yoga"),
        nombreSeancesHistorique: 8
    )
    let sans = SportDetecte(
        typeSport: "Yoga", emoji: "🧘", ilYAMinutes: 60,
        ratioAjuste: nil, nombreSeancesHistorique: 2
    )

    VStack(spacing: 12) {
        SportDetecteCard(sport: avec)
        SportDetecteCard(sport: sans)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
