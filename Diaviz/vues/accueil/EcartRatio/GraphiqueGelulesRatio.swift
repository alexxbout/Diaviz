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
    /// Colonne d'extrémité qui regroupe tout ce qui dépasse la plage :
    /// `.plus` = ce ratio et au-delà (moins d'insuline), `.moins` = ce ratio
    /// et en deçà. `nil` = un seul g/u.
    var extremite: Extremite? = nil

    enum Extremite { case plus, moins }

    var id: Int { grammesParUnite }

    /// Étiquette sous la gélule.
    var libelleCourt: String {
        switch extremite {
        case .plus:  "≥\(grammesParUnite)g"
        case .moins: "≤\(grammesParUnite)g"
        case nil:    "\(grammesParUnite)g"
        }
    }

    /// Libellé du score en tête de carte.
    var libelleRatio: String {
        switch extremite {
        case .plus:  "1u/\(grammesParUnite)g et plus"
        case .moins: "1u/\(grammesParUnite)g et moins"
        case nil:    "1u/\(grammesParUnite)g"
        }
    }

    /// Demi-largeur de la plage détaillée autour du ratio configuré.
    static let demiPlage = 3
    var total: Int { enCible + picModere + hyper + hypo }

    /// Couches de bas en haut — même ordre que la légende.
    var couches: [(Int, Color)] {
        [(enCible, .green), (picModere, .yellow),
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
        var hautDetail = haut + 1, basDetail = max(1, bas - 1)
        // Plage détaillée bornée autour du ratio configuré : au-delà, les
        // repas tombent dans deux gélules d'extrémité. Sinon des ratios
        // extrêmes (corrections, mode avancé) donnaient 20 gélules et plus.
        var extremeHaut: ColonneRatio?, extremeBas: ColonneRatio?
        if let r0 = ratioConfigure {
            if hautDetail > r0 + demiPlage {
                hautDetail = r0 + demiPlage
                extremeHaut = fusion(parRatio.filter { $0.key > hautDetail }.map(\.value),
                                     ratio: hautDetail + 1, extremite: .plus)
            }
            if basDetail < max(1, r0 - demiPlage) {
                basDetail = max(1, r0 - demiPlage)
                extremeBas = fusion(parRatio.filter { $0.key < basDetail }.map(\.value),
                                    ratio: basDetail - 1, extremite: .moins)
            }
        }
        let detail = stride(from: hautDetail, through: basDetail, by: -1).map {
            parRatio[$0] ?? ColonneRatio(grammesParUnite: $0)
        }
        // Une extrémité vide (seule la marge de ± 1 dépassait) n'est pas montrée.
        return [extremeHaut].compactMap { $0 }.filter { $0.total > 0 } + detail
            + [extremeBas].compactMap { $0 }.filter { $0.total > 0 }
    }

    private static func fusion(_ colonnes: [ColonneRatio], ratio: Int, extremite: Extremite) -> ColonneRatio {
        var c = ColonneRatio(grammesParUnite: ratio, extremite: extremite)
        for x in colonnes {
            c.enCible += x.enCible; c.picModere += x.picModere; c.hyper += x.hyper; c.hypo += x.hypo
        }
        return c
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

    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    /// Passe à `true` à l'apparition : les gélules poussent de bas en haut,
    /// en cascade. Le graphique est reconstruit à chaque changement de
    /// moment (`.id` côté page), donc l'animation rejoue à ce moment-là.
    @State private var apparu = false

    /// Largeur minimale d'une colonne : en dessous, les gélules et leurs
    /// libellés se chevauchent. Au-delà de ce que l'écran contient, le
    /// graphique défile horizontalement.
    private let pasMinimal: CGFloat = 34

    var body: some View {
        let maxi = max(1, colonnes.map(\.total).max() ?? 1)
        GeometryReader { geo in
            let pasAjuste = geo.size.width / CGFloat(max(1, colonnes.count))
            if pasAjuste >= pasMinimal {
                contenu(pas: pasAjuste, hauteur: geo.size.height, maxi: maxi)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { valeur in
                        choisir(index: Int(valeur.location.x / pasAjuste))
                    })
            } else {
                // Défilement : le glisser sert à faire défiler, la sélection
                // passe au toucher. Centré sur le ratio actuel à l'arrivée.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        contenu(pas: pasMinimal, hauteur: geo.size.height, maxi: maxi, toucher: true)
                    }
                    .scrollIndicators(.hidden)
                    .task {
                        try? await Task.sleep(for: .milliseconds(150))
                        if let ratioConfigure { proxy.scrollTo(ratioConfigure, anchor: .center) }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        // Marge haute pour « actuel » : même la plus haute gélule, agrandie
        // par la sélection, reste sous le libellé.
        .frame(height: hauteurMax + 60)
        .onAppear { apparu = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilite)
    }

    private func contenu(pas: CGFloat, hauteur: CGFloat, maxi: Int, toucher: Bool = false) -> some View {
        ZStack(alignment: .bottomLeading) {
            zoneRatio(pas: pas, hauteur: hauteur)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(colonnes.enumerated()), id: \.element.id) { i, colonne in
                    colonneVue(colonne, maxi: maxi, largeur: min(22, pas * 0.6), rang: i)
                        .frame(width: pas)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        // Toujours actif : un `onTapGesture` inerte captait le
                        // toucher avant le glisser du conteneur.
                        .onTapGesture { choisir(index: i) }
                        .id(colonne.grammesParUnite)
                }
            }
        }
        .frame(width: pas * CGFloat(colonnes.count), height: hauteur)
    }

    private func choisir(index i: Int) {
        guard colonnes.indices.contains(i) else { return }
        if selection != colonnes[i].grammesParUnite {
            selection = colonnes[i].grammesParUnite
        }
    }

    /// Bande teintée derrière la colonne du ratio configuré : c'est la zone
    /// « ratio » de la comparaison (± 1 g/u). À gauche, moins d'insuline ;
    /// à droite, plus — rappelé sous le graphique.
    @ViewBuilder
    private func zoneRatio(pas: CGFloat, hauteur: CGFloat) -> some View {
        if let i = colonnes.firstIndex(where: { $0.grammesParUnite == ratioConfigure }) {
            VStack(spacing: 2) {
                Text("actuel")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            }
            .frame(width: pas, height: hauteur)
            .offset(x: pas * CGFloat(i))
        }
    }

    private func colonneVue(_ c: ColonneRatio, maxi: Int, largeur: CGFloat, rang: Int) -> some View {
        let hauteur = c.total == 0 ? 8 : hauteurMin + CGFloat(c.total) / CGFloat(maxi) * (hauteurMax - hauteurMin)
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
            .scaleEffect(x: 1, y: apparu || reduireAnimations ? 1 : 0.02, anchor: .bottom)
            .animation(
                reduireAnimations ? nil : .spring(duration: 0.5, bounce: 0.25).delay(Double(rang) * 0.04),
                value: apparu
            )
            .padding(4)

            // Gras = gélule dont le score est affiché en haut, et elle seule.
            Text(c.libelleCourt)
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
