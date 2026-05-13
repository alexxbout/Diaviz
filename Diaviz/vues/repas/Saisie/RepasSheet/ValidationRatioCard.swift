//
//  ValidationRatioCard.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Carte affichant la cohérence entre la dose saisie et la dose suggérée
/// par le ratio actif. 3 variantes selon l'état (cohérente/faible/élevée).
///
/// Design simple : icône en cercle coloré + titre + badge profil + détail,
/// sur un fond uni à `0.10` d'opacité dans la couleur d'accent. Pas de bordure
/// extérieure (qui se faisait clipper par le `Form` parent).
struct ValidationRatioCard: View {

    let validation: ValidationRatio

    @State private var afficherExplication: Bool = false

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
            .background(couleurAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: validation.etat)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $afficherExplication) {
            FeuilleExplicationValidation(validation: validation)
        }
    }

    // MARK: - Sous-vues

    /// Icône circulaire à gauche : fond teinté en accent, glyphe SF Symbol
    /// dans la même couleur d'accent. Donne le focus visuel sur le statut.
    private var iconeCirculaire: some View {
        ZStack {
            Circle()
                .fill(couleurAccent.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: nomIcone)
                .font(.title3.bold())
                .foregroundStyle(couleurAccent)
        }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre)
                .font(.body.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            badgeProfil

            if validation.etat != .coherente {
                Text(ligneEcart)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.top, 2)
            }
        }
    }

    /// Badge profil ratio : capsule teintée d'accent avec icône "détection
    /// auto" et libellé du profil (matin/midi/soir).
    private var badgeProfil: some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
                .font(.caption2.bold())
            Text(validation.profil.description)
                .font(.caption.bold())
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
    }

    // MARK: - Calculs visuels

    private var titre: String {
        switch validation.etat {
        case .coherente: return "Dose cohérente avec le ratio"
        case .faible:    return "Dose faible vs ratio"
        case .elevee:    return "Dose élevée vs ratio"
        }
    }

    private var nomIcone: String {
        switch validation.etat {
        case .coherente:        return "checkmark.circle.fill"
        case .faible, .elevee:  return "exclamationmark.triangle.fill"
        }
    }

    private var ligneEcart: String {
        let saisie = format(validation.doseSaisie)
        let suggeree = format(validation.doseSuggeree)
        let signe = validation.ecart >= 0 ? "+" : ""
        let ecart = "\(signe)\(format(validation.ecart))"
        return "\(saisie)u saisie · \(suggeree)u suggérée · \(ecart)u écart"
    }

    private func format(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }

    private var couleurAccent: Color {
        switch validation.etat {
        case .coherente: return .green
        case .faible:    return .orange
        case .elevee:    return .red
        }
    }

}

// MARK: - Sheet explicative (placeholder)

private struct FeuilleExplicationValidation: View {
    let validation: ValidationRatio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ratio actif") {
                    Text(validation.profil.description)
                }
                Section("Calcul") {
                    LabeledContent("Dose saisie", value: "\(String(format: "%.1f", validation.doseSaisie))u")
                    LabeledContent("Dose suggérée", value: "\(String(format: "%.1f", validation.doseSuggeree))u")
                    LabeledContent("Écart", value: "\(String(format: "%.1f", validation.ecart))u")
                }
                Section {
                    Text("Cette analyse est basée sur ton ratio insuline/glucides moyen sur les dernières semaines, sans tenir compte du sport ni de l'IOB.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Validation du ratio")
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
    let profil = ProfilRatio(unitesPour10g: 1.0, libelle: "midi")
    VStack(spacing: 12) {
        ValidationRatioCard(validation: ValidationRatio(doseSaisie: 9.5, doseSuggeree: 9.5, profil: profil))
        ValidationRatioCard(validation: ValidationRatio(doseSaisie: 0, doseSuggeree: 9.5, profil: profil))
        ValidationRatioCard(validation: ValidationRatio(doseSaisie: 6.5, doseSuggeree: 4.5, profil: profil))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
