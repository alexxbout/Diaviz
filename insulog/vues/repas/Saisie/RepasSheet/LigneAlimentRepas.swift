//
//  LigneAlimentRepas.swift
//  insulog
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Une row de la liste des aliments du repas en cours.
/// Tappable pour éditer, swipe gauche → supprimer (action gérée par le parent
/// via `.swipeActions` au niveau du `ForEach`).
struct LigneAlimentRepas: View {

    let entree: EntreeAliment

    /// Glucides calculés sur la quantité réelle, arrondis à 0.1g.
    private var glucidesEntree: Double { entree.glucides }

    /// Texte secondaire : "100g · 1u" ou "100g · sans insuline".
    private var sousTitre: String {
        let qte = entree.quantiteApproximative
            ? "≈ \(Int(entree.quantiteGrammes))g"
            : "\(Int(entree.quantiteGrammes))g"
        if let dose = entree.doseInsuline, dose > 0 {
            let formatte = dose == floor(dose)
                ? String(format: "%.0fu", dose)
                : String(format: "%.1fu", dose)
            return "\(qte) · \(formatte)"
        } else {
            return qte
        }
    }

    /// Booléen utilitaire pour savoir si on doit colorer "sans insuline" en rouge.
    private var sansInsuline: Bool {
        entree.doseInsuline == nil || entree.doseInsuline == 0
    }

    var body: some View {
        HStack(spacing: 16) {
            // Emoji ou icône de fallback.
            Group {
                if let emoji = entree.aliment.emoji {
                    Text(emoji)
                        .font(.system(size: 32))
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entree.aliment.nom)
                    .font(.body)
                    .lineLimit(2)

                if sansInsuline {
                    HStack(spacing: 4) {
                        Text(qteSeule)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("sans insuline")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.85))
                    }
                } else {
                    Text(sousTitre)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Glucides à droite, monospaced pour aligner les colonnes.
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(String(format: "%.0f", glucidesEntree))
                    .font(.body.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: glucidesEntree)
                Text("g")
                    .font(.caption.bold())
            }
            .foregroundStyle(.green)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // VoiceOver : on combine pour lire la row d'un seul bloc.
        .accessibilityElement(children: .combine)
        .accessibilityHint("Touchez deux fois pour modifier, balayez vers la gauche pour supprimer")
    }

    /// Quantité seule sans la dose, utilisée quand on affiche "sans insuline" en rouge.
    private var qteSeule: String {
        entree.quantiteApproximative
            ? "≈ \(Int(entree.quantiteGrammes))g"
            : "\(Int(entree.quantiteGrammes))g"
    }
}

#Preview {
    let aliment = AlimentCiqual(
        id: 1,
        nom: "Pain complet aux céréales",
        calories: 247,
        glucides: 45,
        sucres: 3,
        proteines: 9,
        lipides: 3,
        fibres: 6,
        emoji: "🍞"
    )
    let entree1 = EntreeAliment(
        aliment: aliment, quantiteGrammes: 60,
        quantiteApproximative: false, doseInsuline: 2.5, note: ""
    )
    let entree2 = EntreeAliment(
        aliment: aliment, quantiteGrammes: 80,
        quantiteApproximative: true, doseInsuline: nil, note: ""
    )

    List {
        LigneAlimentRepas(entree: entree1)
        LigneAlimentRepas(entree: entree2)
    }
}
