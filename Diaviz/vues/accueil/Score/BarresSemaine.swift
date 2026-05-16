//
//  BarresSemaine.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Barres semaine fixes (lundi → dimanche)

/// Composant « semaine » de la page détail :
///   - 7 barres verticales représentant lundi → dimanche de la
///     **semaine contenant** `jourConsulte`. Les barres sont
///     **toujours en position fixe** ; seule la mise en avant
///     (bordure 2pt) se déplace selon `jourConsulte`.
///   - Labels « L M M J V S D » sous les barres.
///
/// Tap sur une barre → `onChangerJour(jour)` (les barres restent en
/// place — c'est la sélection du jour consulté qui bouge). La
/// navigation est restreinte à la semaine de `jourInitial` ;
/// l'utilisateur ne peut pas consulter les semaines précédentes (choix
/// produit : on évite de mettre en exergue des scores historiques).
///
/// Si une journée de la semaine n'a pas de score (futur, ou jour
/// pour lequel le calcul n'a pas encore été fait), sa barre est
/// rendue en gris vide et le tap est ignoré.
struct BarresSemaine: View {

    let jourConsulte: Date
    /// Closure de lecture des données — laissée non-Sendable car
    /// invoquée uniquement depuis le main actor de la vue.
    let scorePourJour: (Date) -> Int?
    let onChangerJour: (Date) -> Void

    private static let hauteurBarres: CGFloat = 72
    private static let largeurBarre: CGFloat = 24
    private static let espacement: CGFloat = 8

    var body: some View {
        VStack(spacing: 10) {
            barresVue
            labelsJours
        }
    }

    // MARK: Barres (7 jours, position fixe)

    private var lundiSemaine: Date {
        lundiDeLaSemaine(jourConsulte)
    }

    private var joursSemaine: [Date] {
        let cal = calendrierFrancais
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: lundiSemaine) }
    }

    private var barresVue: some View {
        HStack(alignment: .bottom, spacing: Self.espacement) {
            ForEach(Array(joursSemaine.enumerated()), id: \.offset) { (_, jour) in
                barreJour(jour: jour, score: scorePourJour(jour))
            }
        }
        .frame(height: Self.hauteurBarres)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func barreJour(jour: Date, score: Int?) -> some View {
        let estActif = calendrierFrancais.isDate(jour, inSameDayAs: jourConsulte)
        let estJourEnCours = calendrierFrancais.isDateInToday(jour)
        let estVide = (score == nil)

        ZStack(alignment: .bottom) {
            // Track gris en fond pour matérialiser la hauteur max — sans
            // ça, un score à 5 / 10 « disparaît » presque, et une barre
            // vide n'a aucune présence visuelle.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(estVide ? 0.08 : 0.12))
                .frame(width: Self.largeurBarre, height: Self.hauteurBarres)

            if let score {
                let couleur = CouleurScore.couleur(pour: score)
                if estJourEnCours {
                    // Jour en cours — barre **hachurée** (stripes
                    // diagonales 45°) sur un fond légèrement teinté.
                    // Le motif hachuré est universellement reconnu
                    // comme "en construction / pas définitif" — bien
                    // plus visible qu'un simple remplissage dilué, et
                    // sans besoin d'animation (la page détail doit
                    // rester calme, contrairement à l'accueil).
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(couleur.opacity(0.18))
                        HachureDiagonale(couleur: couleur)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(width: Self.largeurBarre, height: hauteurBarre(score: score))
                } else {
                    // Jour clôturé — barre pleine, opaque.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(couleur)
                        .frame(width: Self.largeurBarre, height: hauteurBarre(score: score))
                }
            }

            // Bordure de mise en avant sur le jour consulté — posée
            // sur tout le track (pleine hauteur) pour matérialiser la
            // sélection même quand le score est faible.
            if estActif {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                    .frame(width: Self.largeurBarre, height: Self.hauteurBarres)
            }
        }
        .frame(width: Self.largeurBarre, height: Self.hauteurBarres, alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            // Pas de saut sur une barre vide : tap silencieusement
            // ignoré (pas d'animation, pas de changement d'état).
            guard !estVide else { return }
            onChangerJour(jour)
        }
        .accessibilityElement()
        .accessibilityLabel(libelleAccessibilite(jour: jour, score: score, estActif: estActif))
        .accessibilityAddTraits(estVide ? [] : .isButton)
    }

    private func hauteurBarre(score: Int) -> CGFloat {
        let ratio = max(0.05, min(1.0, Double(score) / 100.0))
        return Self.hauteurBarres * ratio
    }

    // MARK: Labels (L M M J V S D)

    private var labelsJours: some View {
        HStack(spacing: Self.espacement) {
            ForEach(Array(joursSemaine.enumerated()), id: \.offset) { (_, jour) in
                Text(initialeJour(jour))
                    .font(.caption2)
                    .foregroundStyle(estJourConsulte(jour) ? .primary : .secondary)
                    .fontWeight(estJourConsulte(jour) ? .semibold : .regular)
                    .frame(width: Self.largeurBarre)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func estJourConsulte(_ jour: Date) -> Bool {
        calendrierFrancais.isDate(jour, inSameDayAs: jourConsulte)
    }

    /// Initiale française du jour de la semaine. Calendrier forcé en
    /// lundi-premier pour rester cohérent avec l'ordre des barres.
    private func initialeJour(_ jour: Date) -> String {
        let cal = calendrierFrancais
        let weekday = cal.component(.weekday, from: jour) // 1=dim, 2=lun, ..., 7=sam
        let initiales = ["D", "L", "M", "M", "J", "V", "S"]
        return initiales[(weekday - 1 + 7) % 7]
    }

    // MARK: Accessibilité

    private func libelleAccessibilite(jour: Date, score: Int?, estActif: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        let dateStr = formatter.string(from: jour).capitalizedFirst
        guard let score else {
            return "\(dateStr), pas de données disponibles"
        }
        if estActif {
            return "\(dateStr), score \(score) sur 100, jour consulté"
        }
        return "\(dateStr), score \(score) sur 100, toucher pour consulter ce jour"
    }
}

// MARK: - Motif hachuré (jour en cours)

/// Stripes diagonales à 45° dessinées via `Canvas` — utilisé pour
/// remplir la barre du jour en cours dans `BarresSemaine` sans avoir
/// recours à une animation ou à une opacité globale qui rend la barre
/// peu lisible.
///
/// Les lignes vont du coin haut-gauche au coin bas-droit (orientation
/// "descendante" — la convention la plus courante pour signaler une
/// zone en travaux ou en attente). Le pas (`espacement + largeurTrait`)
/// reste constant : le motif a la même densité quelle que soit la
/// hauteur de la barre.
///
/// Le clipping aux coins arrondis est fait par le parent
/// (`.clipShape(RoundedRectangle…)`), pas ici — `HachureDiagonale`
/// remplit naturellement son cadre rectangulaire.
private struct HachureDiagonale: View {

    let couleur: Color
    var espacement: CGFloat = 4
    var largeurTrait: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let pas = espacement + largeurTrait
            // `c` est l'abscisse au point haut de chaque ligne. On
            // sweep de 0 à `size.width + size.height` pour couvrir
            // tout le rectangle : aux extrémités, la ligne déborde
            // hors du cadre — c'est le clipping du parent qui ramène
            // dans la forme arrondie.
            var c: CGFloat = 0
            while c <= size.width + size.height {
                var trace = Path()
                trace.move(to: CGPoint(x: c, y: 0))
                trace.addLine(to: CGPoint(x: c - size.height, y: size.height))
                context.stroke(
                    trace,
                    with: .color(couleur),
                    lineWidth: largeurTrait
                )
                c += pas
            }
        }
    }
}
