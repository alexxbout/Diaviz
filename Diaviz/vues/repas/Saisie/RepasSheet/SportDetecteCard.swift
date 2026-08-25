//
//  SportDetecteCard.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Carte affichée quand un sport a été détecté dans la fenêtre récente.
/// Indique si on a un ratio ajusté disponible (basé sur l'historique) ou
/// si on n'a pas encore assez de données.
///
/// Design aligné sur les autres cartes : icône en cercle bleu à gauche,
/// titre + ratio ajusté + détail à droite, fond uni à `0.10` d'opacité.
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
            .surfaceCarte(fond: couleurAccent.opacity(0.10))
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
            Label("\(sport.typeSport) détecté il y a \(libelleTemps)", systemImage: sport.icone)
                .font(.body.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Text(messageContextuel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var libelleTemps: String {
        let m = sport.ilYAMinutes
        if m < 60 { return "\(m)min" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h\(r)"
    }

    /// Dit d'où vient le ratio en vigueur, sans répéter son chiffre — il est
    /// affiché une seule fois, dans la carte de validation de la dose.
    /// L'ancien message (« basé sur N séances ») attribuait à un historique
    /// inexistant un ratio qui venait du profil : le décompte était figé à 0
    /// et le mining par type de sport n'existe pas encore (S1/R2).
    private var messageContextuel: String {
        sport.ratioAjuste != nil
            ? "Ton ratio post-\(sport.typeSport.lowercased()) est appliqué à la dose de ce repas."
            : "Aucun ratio post-\(sport.typeSport.lowercased()) configuré : le ratio du moment reste appliqué."
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
                    LabeledContent("Type") {
                        Label(sport.typeSport, systemImage: sport.icone)
                    }
                    LabeledContent("Il y a", value: "\(sport.ilYAMinutes) min")
                }
                if let ratio = sport.ratioAjuste {
                    Section("Ratio appliqué") {
                        Text(ratio.description)
                        Text("Saisi dans ton profil, section Ratios sport.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Le sport peut modifier la sensibilité à l'insuline pendant plusieurs heures. Le ratio appliqué ici est celui que tu as renseigné pour ce type d'activité — Diaviz ne le déduit pas de ton historique.")
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

#if DEBUG
#Preview {
    let avec = SportDetecte(
        typeSport: "Yoga", icone: "figure.yoga", ilYAMinutes: 60,
        ratioAjuste: ProfilRatio(grammesParUnite: 14, libelle: "post-yoga")
    )
    let sans = SportDetecte(
        typeSport: "Yoga", icone: "figure.yoga", ilYAMinutes: 60,
        ratioAjuste: nil
    )

    VStack(spacing: 12) {
        SportDetecteCard(sport: avec)
        SportDetecteCard(sport: sans)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
#endif
