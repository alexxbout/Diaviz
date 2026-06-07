//
//  SheetComparerCeSoir.swift
//  diaviz
//
//  Created by Alexandre on 31/05/2026.
//

import SwiftUI

/// Sheet « Comparer à ce soir » — la surface de **recherche par similarité**
/// (k-NN, V1.1) du coucher.
///
/// L'utilisateur saisit sa glycémie actuelle (le CGM ayant 3h de retard) ; le
/// reste du contexte (sport, IOB, lente, charge) est déjà connu de l'app. La
/// recherche remonte les nuits passées **proches**, scindées « fini en hypo /
/// resté stable », pour répondre à : « est-ce que je peux me coucher comme ça ? »
///
/// **Glucose-agnostique** : route selon la glycémie saisie — basse → analogues
/// d'endormissement (B2), haute → corrections (B3, à venir).
///
/// Des faits, jamais un conseil de glucides ou de dose.
struct SheetComparerCeSoir: View {

    let analyse: AnalyseEndormissement

    @Environment(\.dismiss) private var dismiss

    @State private var glycemieTexte = ""
    @State private var rechercheLancee = false
    @FocusState private var champFocus: Bool

    // Contexte de « ce soir » — mocké en V0 (sera fourni par l'app).
    private let sportCeSoir = false
    private let iobCeSoir: Double? = nil
    private let chargeCeSoir: ChargeActivite = .moderee

    /// Demi-largeur de la bande de similarité sur la glycémie (mg/dL).
    private let bande = 15

    private var glycemie: Int? { Int(glycemieTexte) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    saisie
                    recapContexte
                    boutonRecherche
                    if rechercheLancee { resultats }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Comparer à ce soir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: - Saisie glycémie

    private var saisie: some View {
        VStack(spacing: 6) {
            Text("Ta glycémie maintenant")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("—", text: $glycemieTexte)
                .keyboardType(.numberPad)
                .focused($champFocus)
                .multilineTextAlignment(.center)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .onChange(of: glycemieTexte) { rechercheLancee = false }
            Text("mg/dL")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    // MARK: - Récap contexte de ce soir

    private var recapContexte: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ce soir")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                pastilleContexte(systeme: "syringe.fill", texte: "\(analyse.doseActuelle.formatted()) u")
                BadgeChargeActivite(charge: chargeCeSoir)
                if sportCeSoir {
                    pastilleContexte(systeme: "figure.run", texte: "sport")
                }
                pastilleContexte(systeme: "drop.fill",
                                 texte: iobCeSoir.map { String(format: "%.1fU", $0) } ?? "0 IOB")
                Spacer(minLength: 0)
            }
        }
    }

    private func pastilleContexte(systeme: String, texte: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systeme)
            Text(texte).monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Bouton recherche

    private var boutonRecherche: some View {
        Button {
            champFocus = false
            withAnimation(.easeInOut(duration: 0.2)) { rechercheLancee = true }
        } label: {
            Text("Lancer la recherche")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(glycemie == nil)
    }

    // MARK: - Résultats

    @ViewBuilder
    private var resultats: some View {
        if let g = glycemie {
            if g > analyse.seuilCoucher {
                messageInfo("Tu es au-dessus du seuil analysé (\(analyse.seuilCoucher) mg/dL). L'analyse des corrections du soir (B3) arrivera ici.")
            } else {
                let proches = analyse.nuits.filter { abs($0.glycemieCoucher - g) <= bande }
                if proches.isEmpty {
                    messageInfo("Aucune nuit comparable à ±\(bande) mg/dL. Pas de quoi conclure.")
                } else {
                    let hypos = proches.filter { $0.issue.estHypo }
                    let stables = proches.filter { !$0.issue.estHypo }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(proches.count) nuits à ±\(bande) mg/dL de \(g)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !hypos.isEmpty {
                            groupe(titre: "Fini en hypo", n: hypos.count, couleur: .red, nuits: hypos)
                        }
                        if !stables.isEmpty {
                            groupe(titre: "Resté stable", n: stables.count, couleur: .green, nuits: stables)
                        }
                    }
                }
            }
        }
    }

    private func groupe(titre: String, n: Int, couleur: Color, nuits: [NuitEndormissement]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(couleur)
                    .frame(width: 9, height: 9)
                Text(titre)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(couleur)
                Text("·").foregroundStyle(.tertiary)
                Text("\(n)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(nuits.enumerated()), id: \.element.id) { index, nuit in
                    if index > 0 { Divider().padding(.leading, 16) }
                    ligneResultat(nuit)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        }
    }

    private func ligneResultat(_ nuit: NuitEndormissement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Ligne 1 — glycémie (titre) + délai d'hypo éventuel
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text("\(nuit.glycemieCoucher)")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Image(systemName: nuit.tendance.symbole)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if case let .hypo(delai) = nuit.issue {
                    Text(delaiRelatif(delai))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }
            }
            // Ligne 2 — contexte (sous-titre nu)
            HStack(spacing: 12) {
                BadgeChargeActivite(charge: nuit.charge, avecLibelle: true)
                if let s = nuit.sport {
                    BadgeSport(seance: s)
                }
                if let iob = nuit.iob {
                    contexteItem(systeme: "drop.fill", texte: String(format: "%.1fU", iob))
                }
                if let g = nuit.glucides {
                    contexteItem(systeme: "fork.knife", texte: "\(g.formatted())g")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func contexteItem(systeme: String, texte: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systeme)
            Text(texte).monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func messageInfo(_ texte: String) -> some View {
        Text(texte)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    private func delaiRelatif(_ minutes: Int) -> String {
        if minutes < 60 { return "t+\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "t+\(h) h" : "t+\(h) h \(m)"
    }
}

// MARK: - Aperçu

#Preview("Comparer à ce soir") {
    SheetComparerCeSoir(analyse: .mock)
}
