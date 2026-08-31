//
//  IconeGlucides.swift
//  diaviz
//

/// Emoji du domaine « glucides », partagé par la carte d'accueil, son
/// placeholder et l'en-tête de la page de détail.
///
/// Un emoji plutôt qu'un SF Symbol parce qu'aucun symbole système ne
/// représente un fruit — `apple.logo` est le logo de la marque, pas une
/// pomme. L'app affiche déjà ses aliments en emoji, la grammaire tient.
///
/// Constante partagée pour que les trois écrans ne divergent jamais : c'est
/// exactement ce qui était arrivé aux rayons de coin avant `Radius`.
enum IconeGlucides {
    static let emoji = "🍎"
}
