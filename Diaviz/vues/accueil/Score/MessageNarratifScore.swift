//
//  MessageNarratifScore.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Message narratif (LLM)

/// Encapsule la génération Foundation Models pour ce jour. Même
/// pipeline que `SheetScoreMatin` (`NarrationViewModel`), avec le
/// même rendu sobre — texte `.body .secondary` + disclaimer IA en
/// `.caption .tertiary` italique.
struct MessageNarratifScore: View {

    let faits: FaitsJour

    @State private var modele = NarrationViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                LoaderPoints()
                    .opacity(estChargement ? 1 : 0)

                Text(texteAffiche)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(estChargement ? 0 : 1)
            }
            .animation(.easeOut(duration: 0.4), value: estChargement)

            if afficherDisclaimerIA {
                Text("Contenu généré par IA, à vérifier.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: faits) {
            await modele.demarrer(faits: faits)
        }
    }

    private var estChargement: Bool {
        if case .chargement = modele.etat { return true }
        return false
    }

    private var afficherDisclaimerIA: Bool {
        switch modele.etat {
        case .streaming, .termine: return true
        case .chargement, .fallback: return false
        }
    }

    private var texteAffiche: String {
        switch modele.etat {
        case .chargement:        return ""
        case .streaming(let s):  return phraseConcatenee(s)
        case .termine(let s):    return phraseConcatenee(s)
        case .fallback(let t):   return t
        }
    }

    /// Mêmes règles de séparation que `SheetScoreMatin` — filet de
    /// sécurité si le LLM oublie les espaces entre segments.
    private func phraseConcatenee(_ segments: [SegmentNarration]) -> String {
        var resultat = ""
        var precedent: SegmentNarration?
        for segment in segments {
            if besoinSeparateur(precedent: precedent, suivant: segment) {
                resultat.append(" ")
            }
            resultat.append(segment.text)
            precedent = segment
        }
        return resultat
    }

    private func besoinSeparateur(
        precedent: SegmentNarration?,
        suivant: SegmentNarration
    ) -> Bool {
        guard let precedent else { return false }
        guard let dernierCar = precedent.text.last,
              let premierCar = suivant.text.first else { return false }
        if dernierCar.isWhitespace || premierCar.isWhitespace { return false }
        if ",.;:!?)»".contains(premierCar) { return false }
        if "(«".contains(dernierCar) { return false }
        return true
    }
}
