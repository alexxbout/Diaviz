//
//  GraphiqueGelulesRatio.swift
//  diaviz
//

import SwiftUI

/// Repas d'un même ratio effectif (arrondi au g/u), ventilés par résultat.
struct ColonneRatio: Identifiable, Equatable {
    let grammesParUnite: Int
    var enCible = 0
    var picModere = 0
    var hyper = 0
    var hypo = 0

    var id: Int { grammesParUnite }
    var total: Int { enCible + picModere + hyper + hypo }

    /// Couches de bas en haut — même ordre que la légende.
    var couches: [(Int, Color)] {
        [(enCible, .green), (picModere, .orange),
         (hyper, RaisonMauvaisVerdict.hyperglycemie.couleur),
         (hypo, RaisonMauvaisVerdict.hypoglycemie.couleur)]
    }

    /// Une colonne par g/u entre le plus petit et le plus grand ratio
    /// observé (± 1), ratio configuré inclus. Les trous restent visibles :
    /// ils disent qu'aucun repas n'a été fait à ce ratio.
    /// Ordre : g/u décroissant, donc « moins d'insuline » à gauche.
    static func colonnes(entrees: [EntreeRatioRepas], ratioConfigure: Int?) -> [ColonneRatio] {
        var parRatio: [Int: ColonneRatio] = [:]
        for e in entrees where e.doseAppliquee > 0 && e.glucides > 0 {
            let g = Int((Double(e.glucides) / e.doseAppliquee).rounded())
            var c = parRatio[g] ?? ColonneRatio(grammesParUnite: g)
            switch e.verdict {
            case .bon: c.enCible += 1
            case .moyen: c.picModere += 1
            case .mauvais:
                if e.raisonMauvais == .hypoglycemie { c.hypo += 1 } else { c.hyper += 1 }
            case .indetermine: continue
            }
            parRatio[g] = c
        }
        let bornes = Array(parRatio.keys) + (ratioConfigure.map { [$0] } ?? [])
        guard let bas = bornes.min(), let haut = bornes.max() else { return [] }
        return stride(from: haut + 1, through: max(1, bas - 1), by: -1).map {
            parRatio[$0] ?? ColonneRatio(grammesParUnite: $0)
        }
    }
}

/// Une gélule par ratio : hauteur = nombre de repas, remplissage de bas en
/// haut par résultat. Aucun chiffre sur les gélules — le toucher met à jour
/// le score de l'en-tête, qui porte déjà « x sur n repas ».
struct GraphiqueGelulesRatio: View {
    let colonnes: [ColonneRatio]
    let ratioConfigure: Int?
    @Binding var selection: Int?

    private let hauteurMax: CGFloat = 120
    private let hauteurMin: CGFloat = 18

    var body: some View {
        let maxi = max(1, colonnes.map(\.total).max() ?? 1)
        GeometryReader { geo in
            let pas = geo.size.width / CGFloat(max(1, colonnes.count))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(colonnes) { colonne in
                    colonneVue(colonne, maxi: maxi, largeur: min(22, pas * 0.6))
                        .frame(width: pas)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { valeur in
                let i = Int(valeur.location.x / pas)
                guard colonnes.indices.contains(i) else { return }
                if selection != colonnes[i].grammesParUnite {
                    selection = colonnes[i].grammesParUnite
                }
            })
            .sensoryFeedback(.selection, trigger: selection)
        }
        .frame(height: hauteurMax + 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilite)
    }

    private func colonneVue(_ c: ColonneRatio, maxi: Int, largeur: CGFloat) -> some View {
        let hauteur = c.total == 0 ? 8 : hauteurMin + CGFloat(c.total) / CGFloat(maxi) * (hauteurMax - hauteurMin)
        let estActuel = c.grammesParUnite == ratioConfigure
        let estChoisi = c.grammesParUnite == selection
        return VStack(spacing: 6) {
            // Les résultats remplissent la gélule de bas en haut.
            VStack(spacing: 0) {
                ForEach(Array(c.couches.reversed().enumerated()), id: \.offset) { _, couche in
                    if couche.0 > 0 {
                        couche.1.opacity(0.85)
                            .frame(height: hauteur * CGFloat(couche.0) / CGFloat(c.total))
                    }
                }
            }
            .frame(width: largeur, height: hauteur, alignment: .bottom)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
            // Sélection : liseré blanc épais posé sur les couleurs + ombre,
            // lisible sur n'importe quel remplissage.
            .overlay {
                if estChoisi { Capsule().strokeBorder(.white, lineWidth: 3) }
            }
            .shadow(color: .black.opacity(estChoisi ? 0.3 : 0), radius: 4, y: 1)
            .scaleEffect(estChoisi ? 1.08 : 1, anchor: .bottom)
            .padding(4)
            // Ratio actuel : fin contour extérieur, distinct de la sélection.
            .overlay {
                if estActuel { Capsule().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
            }

            // Gras = gélule dont le score est affiché en haut, et elle seule.
            Text("\(c.grammesParUnite)g")
                .font(.caption2.weight(estChoisi ? .bold : .regular))
                .foregroundStyle(estChoisi ? .primary : .secondary)
                .monospacedDigit()
        }
    }

    private var accessibilite: String {
        colonnes.filter { $0.total > 0 }.map {
            "1 unité pour \($0.grammesParUnite) grammes : \($0.enCible) en cible sur \($0.total)"
        }.joined(separator: ". ")
    }
}
