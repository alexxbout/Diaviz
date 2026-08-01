//
//  LigneRepasARevoir.swift
//  diaviz
//

import SwiftUI

/// Forme **compacte** d'un repas à revoir — utilisée pour les repas du
/// groupe qui ne sont pas actuellement étendus (voir `SectionRepasARevoir`).
/// Un tap échange cette ligne avec la carte détaillée actuellement étendue
/// (`CarteRepasARevoir`) — simple transition d'apparition/disparition, pas de
/// morph partagé (essayé puis abandonné : `matchedGeometryEffect` entre une
/// ligne fine et une carte contenant un `Chart` interpole mal, le graphe
/// n'étant pas lui-même une géométrie partagée — le résultat était saccadé).
///
/// Ne garde que ce qui permet de reconnaître et de trier : moment de la
/// journée (titre, comme la carte détaillée — même vocabulaire), verdict +
/// ratio, icônes d'aliments. Le détail (nuage des occurrences, événements du
/// hub, graphe) n'apparaît qu'une fois étendue.
struct LigneRepasARevoir: View {

    let repas: RepasARevoir

    let onTap: () -> Void

    private static let maxIconesAliments = 3

    /// Même geste et même confirmation que `CarteRepasARevoir` : masquer
    /// doit marcher qu'un repas soit actuellement étendu ou compact.
    @State private var confirmerMasquage = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repas.libelleSection.isEmpty ? "Repas" : repas.libelleSection)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(repas.libelleEvenement)
                            .foregroundStyle(repas.couleurSeverite)
                        if let ratio = repas.ratioFormate {
                            Text("· \(ratio)")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                iconesAliments

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                confirmerMasquage = true
            }
        )
        .confirmationDialog(
            "Masquer ce repas ?",
            isPresented: $confirmerMasquage,
            titleVisibility: .visible
        ) {
            Button("Masquer", role: .destructive) {
                RepasARevoirMasquesService.shared.masquer(repas.idRepasSource)
            }
        } message: {
            Text("Il réapparaîtra automatiquement s'il se reproduit avec un nouveau résultat hors cible.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibilite)
        .accessibilityHint("Développe le détail de ce repas")
        .accessibilityAction(named: "Masquer") { confirmerMasquage = true }
    }

    /// Icônes tronquées à 3 + « +N » — même logique que la carte détaillée,
    /// en plus compact pour tenir dans la hauteur d'une ligne.
    private var iconesAliments: some View {
        HStack(spacing: 4) {
            ForEach(Array(repas.aliments.prefix(Self.maxIconesAliments))) { aliment in
                Group {
                    if let url = aliment.imageURL {
                        ImageProduit(url: url, coinArrondi: 6)
                    } else {
                        Text(aliment.emoji).font(.footnote)
                    }
                }
                .frame(width: 22, height: 22)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            }
            let reste = repas.aliments.count - Self.maxIconesAliments
            if reste > 0 {
                Text("+\(reste)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private var libelleAccessibilite: String {
        let nom = repas.libelleSection.isEmpty ? "Repas" : repas.libelleSection
        let ratio = repas.ratioFormate.map { ", ratio \($0)" } ?? ""
        return "\(nom). \(repas.libelleEvenement)\(ratio)."
    }
}

// MARK: - Aperçus

#Preview("Lignes compactes") {
    VStack(spacing: 0) {
        LigneRepasARevoir(repas: .mockPadThai, onTap: {})
        Divider().padding(.leading, 16)
        LigneRepasARevoir(repas: .mockPizza, onTap: {})
        Divider().padding(.leading, 16)
        LigneRepasARevoir(repas: .mockSushi, onTap: {})
    }
    .surfaceCarte()
    .padding()
    .background(Color(.systemGroupedBackground))
}
