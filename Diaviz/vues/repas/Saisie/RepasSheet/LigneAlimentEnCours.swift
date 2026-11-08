//
//  LigneAlimentEnCours.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Row d'un aliment déjà ajouté au repas **en cours de composition**
/// (`RepasSheet`) — quantité et dose saisies, encore modifiables tant que le
/// repas n'est pas validé. Tappable pour éditer, swipe gauche → supprimer
/// (action gérée par le parent via `.swipeActions` au niveau du `ForEach`).
///
/// À ne pas confondre avec les deux autres rows du domaine repas :
/// - `LigneResultatRecherche` (Saisie/) : un résultat de recherche, pas
///   encore ajouté au repas.
/// - `CarteAlimentEnregistre` (composants/) : l'aliment tel qu'affiché dans un
///   repas déjà persisté dans le hub (journal, détail), en lecture seule.
struct LigneAlimentEnCours: View {

    let entree: EntreeAliment

    /// Glucides calculés sur la quantité réelle, arrondis à 0.1g.
    private var glucidesEntree: Double { entree.glucides }

    /// Texte secondaire : "100g · 2× 50g · 1u".
    private var sousTitre: String {
        if let dose = entree.doseInsuline, dose > 0 {
            return "\(qteSeule) · \(dose.doseInsulineFormatee)"
        } else {
            return qteSeule
        }
    }

    /// Booléen utilitaire pour savoir si on doit colorer "sans insuline" en rouge.
    private var sansInsuline: Bool {
        entree.doseInsuline == nil || entree.doseInsuline == 0
    }

    var body: some View {
        HStack(spacing: 16) {
            // Emoji, photo produit (OFF) ou icône de fallback.
            VignetteAliment(aliment: entree.aliment, taille: 40)

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

    /// Quantité sans la dose, utilisée quand on affiche "sans insuline" en rouge.
    private var qteSeule: String {
        let grammes = entree.quantiteApproximative
            ? "≈ \(Int(entree.quantiteGrammes))g"
            : "\(Int(entree.quantiteGrammes))g"
        return portions.map { "\(grammes) · \($0)" } ?? grammes
    }

    /// « 2× 50g » pour un aliment saisi en portions, `nil` sinon. Une quantité
    /// saisie en grammes ne se traduit pas en portions (« 2,6× 50g »).
    private var portions: String? {
        guard entree.modeQuantite == .portions,
              let taille = AlimentsRecentsService.shared.tailleDePortion(entree.aliment),
              taille > 0 else { return nil }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        return "\((entree.quantiteGrammes / taille).formatted(format))× \(taille.formatted(format))g"
    }
}

#if DEBUG
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
        aliment: .ciqual(aliment), quantiteGrammes: 60,
        quantiteApproximative: false, doseInsuline: 2.5, note: ""
    )
    let entree2 = EntreeAliment(
        aliment: .ciqual(aliment), quantiteGrammes: 80,
        quantiteApproximative: true, doseInsuline: nil, note: ""
    )

    List {
        LigneAlimentEnCours(entree: entree1)
        LigneAlimentEnCours(entree: entree2)
    }
}
#endif
