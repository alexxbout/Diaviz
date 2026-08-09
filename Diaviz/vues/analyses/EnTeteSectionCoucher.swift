//
//  EnTeteSectionCoucher.swift
//  diaviz
//
//  Created by Alexandre on 30/05/2026.
//

import SwiftUI

/// En-tête d'une section de la page « Analyse du coucher ».
///
/// Posé en haut de chaque section (dans un `VStack`), il défile avec le
/// contenu. Titre proéminent + statut glance (réutilise `StatutSousAnalyseVue`,
/// même rendu que la carte sommaire) + bouton ⓘ optionnel + chevron rotatif.
/// Tap sur l'en-tête (hors ⓘ) → `onToggle`.
struct EnTeteSectionCoucher: View {

    let titre: String
    let etat: EtatSousAnalyse
    let ouverte: Bool
    var onInfo: (() -> Void)? = nil
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(titre)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            StatutSousAnalyseVue(etat: etat)

            Spacer(minLength: 8)

            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)   // exposé via accessibilityAction
            }

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(ouverte ? 90 : 0))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider().opacity(ouverte ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(ouverte ? "Replier la section" : "Déplier la section")
        .accessibilityAction(named: Text("Comment ça marche")) { onInfo?() }
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("En-têtes de section") {
    ScrollView {
        VStack(spacing: 0) {
            EnTeteSectionCoucher(
                titre: "Tendance basale",
                etat: .resultat(libelle: "Adaptée", ton: .positif),
                ouverte: true,
                onInfo: {},
                onToggle: {}
            )
            Color.clear.frame(height: 200)
            EnTeteSectionCoucher(
                titre: "Endormissement",
                etat: .resultat(libelle: "2 hypos", ton: .attention),
                ouverte: false,
                onInfo: {},
                onToggle: {}
            )
        }
    }
    .background(Color(.systemGroupedBackground))
}
#endif
