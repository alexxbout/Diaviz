//
//  SurfaceCarte.swift
//  diaviz
//

import SwiftUI

/// Niveau hiérarchique d'une surface card-like — détermine son corner
/// radius depuis les tokens `Radius`.
///
/// Trois niveaux, pas plus : c'est la seule échelle sanctionnée. Une carte
/// qui « aurait besoin » d'une quatrième valeur est en fait une carte de
/// l'un de ces trois niveaux mal identifiée.
enum NiveauCarte {

    /// **Toute carte posée sur le fond de page** : score du jour, analyse
    /// des ratios, aperçu du jour, sections du journal, blocs des pages de
    /// détail, graphes de journée. `Radius.large` (22pt).
    ///
    /// C'est le défaut, et il n'y a **pas** de sous-palier « carte un peu
    /// moins importante » : deux cartes qui se suivent verticalement sur le
    /// même fond doivent avoir exactement le même arrondi, sinon l'œil lit
    /// un défaut, pas une hiérarchie.
    case carte

    /// Surface **imbriquée dans une carte** — un bloc encadré à l'intérieur
    /// d'une carte existante. `Radius.medium` (18pt). Rare : la plupart des
    /// surfaces qui semblent imbriquées sont en fait des `.compact`.
    case imbriquee

    /// Éléments compacts internes : chips, badges, tags, sélecteurs
    /// radio/segment, boutons internes. `Radius.small` (10pt).
    case compact

    var rayon: CGFloat {
        switch self {
        case .carte:     Radius.large
        case .imbriquee: Radius.medium
        case .compact:   Radius.small
        }
    }

    /// Forme de la surface — `RoundedRectangle` continu (jamais `.circular`,
    /// qui jure avec le langage visuel iOS).
    var forme: RoundedRectangle {
        RoundedRectangle(cornerRadius: rayon, style: .continuous)
    }
}

// MARK: - Surfaces opaques

extension View {

    /// Applique le fond de carte standard de l'app : fond
    /// `secondarySystemGroupedBackground`, radius du niveau, contenu clippé
    /// et zone de tap alignée sur la forme.
    ///
    /// À préférer systématiquement à un `.background(… RoundedRectangle …)`
    /// écrit à la main : le clip et la `contentShape` sont la source des
    /// incohérences d'arrondi perçues (un contenu pleine largeur qui déborde
    /// du coin, une zone de tap rectangulaire sur une carte arrondie).
    func surfaceCarte(_ niveau: NiveauCarte = .carte) -> some View {
        surfaceCarte(niveau, fond: Color(.secondarySystemGroupedBackground))
    }

    /// Variante avec un fond explicite (teinte d'accent, matière, dégradé).
    func surfaceCarte<S: ShapeStyle>(
        _ niveau: NiveauCarte = .carte,
        fond: S
    ) -> some View {
        let forme = niveau.forme
        return self
            .background(fond, in: forme)
            .clipShape(forme)
            .contentShape(forme)
    }
}

// MARK: - Surfaces en verre

extension View {

    /// Applique une surface **Liquid Glass** au niveau demandé, teintée si
    /// `teinte` est fourni.
    ///
    /// Pas de `.interactive()` : sur une carte qui pousse une page,
    /// l'animation de déformation du verre au press se joue avant le push et
    /// se lit comme du lag — la transition de navigation est déjà le
    /// feedback. Les contrôles qui agissent sur place (boutons du HUD de
    /// séance) appellent `glassEffect` directement avec `.interactive()`.
    func surfaceCarteVerre(
        _ niveau: NiveauCarte = .carte,
        teinte: Color? = nil
    ) -> some View {
        let forme = niveau.forme
        return self
            .glassEffect(
                teinte.map { .regular.tint($0) } ?? .regular,
                in: forme
            )
            .contentShape(forme)
    }
}
