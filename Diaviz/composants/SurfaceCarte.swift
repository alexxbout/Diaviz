//
//  SurfaceCarte.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

extension View {

    /// Surface standard d'une **carte de l'accueil** : fond opaque
    /// `secondarySystemGroupedBackground` + radius `Radius.medium`,
    /// sans ombre ni bordure.
    ///
    /// Source unique de vérité pour la surface des cartes — un changement
    /// de design (radius, ombre, bordure subtile) se propage automatiquement
    /// à tous les sites consommateurs (`CarteInsight`, `CarteLenteRappel`,
    /// `CarteRepasARevoir`, `CarteMetriqueShell`).
    ///
    /// Pattern `background + clipShape` (et pas `background { Shape.fill }`)
    /// pour que les sous-vues débordantes soient correctement rognées par
    /// la forme arrondie — comportement cohérent avec les cellules de
    /// `List.insetGrouped`.
    func surfaceCarte() -> some View {
        self
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}
