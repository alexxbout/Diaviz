//
//  Radius.swift
//  diaviz
//
//  Created by Alexandre on 15/05/2026.
//

import CoreGraphics

/// Tokens de **corner radius** pour toutes les surfaces card-like de
/// l'app — source unique de vérité pour homogénéiser le langage visuel.
///
/// L'app utilisait initialement 7 valeurs distinctes (8, 10, 12, 14,
/// 16, 20pt) écrites en dur dans chaque composant — c'est devenu
/// incohérent : la grille d'accueil en 16pt jouxtait des cartes
/// insight en 20pt qui jouxtaient elles-mêmes une carte score en 12pt.
///
/// 3 paliers couvrent tous les besoins :
///
/// - `small` = **10pt** — chips, badges, boutons internes, sélecteurs
/// - `medium` = **18pt** — cartes standard (grille, sections, liste)
/// - `large` = **22pt** — cartes **hero** (score du jour, insights)
///
/// ## Convention d'usage
///
/// Ne pas appeler ces tokens directement pour une surface de carte :
/// passer par `.surfaceCarte(_:)` / `.surfaceCarteVerre(_:teinte:)`
/// (voir `SurfaceCarte.swift`), qui appliquent fond + `clipShape` +
/// `contentShape` d'un bloc. Écrire le `.background(… RoundedRectangle …)`
/// à la main est précisément ce qui a produit les incohérences d'arrondi :
/// on oublie le clip, le contenu pleine largeur déborde du coin, et deux
/// cartes au même token n'ont pas le même arrondi perçu.
///
/// Les tokens restent utilisés directement pour les cas hors périmètre
/// (formes de `glowIntelligence`, bordures composées). **Aucun nombre en
/// dur** pour un radius de carte.
///
/// Pour les éléments **imbriqués** qui doivent suivre la forme du
/// parent, préférer `.containerRelativeShape` (iOS 14+) ou
/// `ConcentricRectangle` (iOS 26) qui calculent automatiquement le
/// radius interne concentrique.
///
/// ## Exceptions documentées
///
/// - `BulleRepasEnCours` : 100pt (pill par design, pas une carte)
/// - Mini-barres de chart : 1.5–6pt (micro-éléments internes, hors
///   périmètre des tokens)
enum Radius {

    /// Petits éléments : chips, badges, boutons internes, sélecteurs
    /// radio/segment. Discret, contenu compact.
    static let small: CGFloat = 10

    /// Cartes standard : grille de l'accueil, sections du journal,
    /// items de liste. Généreux sans être ostentatoire.
    static let medium: CGFloat = 18

    /// Cartes **hero** affichées en haut de page (carte score, carte
    /// insights de l'accueil). Crée une légère hiérarchie visuelle vs
    /// les cartes `medium` en dessous.
    static let large: CGFloat = 22
}
