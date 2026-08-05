//
//  CarteScoreQuotidien.swift
//  diaviz
//
//  Created by Alexandre on 06/05/2026.
//

import SwiftUI
import Charts

// MARK: - Modèles publics

/// Données affichées par `CarteScoreQuotidien`. Partagée entre les
/// variants de style pour garantir une cohérence d'affichage.
///
/// Modèle "score du jour" : le `score` représente la journée
/// **courante** (recalculée en temps réel sur la convention 06h-06h),
/// et la 7ᵉ barre de l'historique est rendue en mode "en cours" —
/// partiellement remplie selon `heuresJourEcoulees` et entourée d'une
/// bordure pointillée pulsante.
struct ContenuCarteScore: Sendable, Equatable {
    /// Score sur 100 — `nil` quand la couverture CGM est insuffisante.
    let score: Int?
    /// Date du jour affiché (le dernier élément d'`historique`).
    let date: Date
    /// 7 derniers scores, du plus ancien au plus récent. Les valeurs
    /// `nil` sont rendues en barres atténuées. Le dernier élément est
    /// le score partiel du jour courant.
    let historique: [Int?]
    /// Heures écoulées depuis 06h ce matin (0 à 24). Pilote le
    /// remplissage partiel de la 7ᵉ barre et le sous-texte
    /// "Xh de données".
    let heuresJourEcoulees: Double
    /// `true` si la carte montre le **jour en cours** (partiel) ; `false` si elle
    /// montre un **jour complet** (bascule sur la veille tant que le jour en
    /// cours n'a pas assez de données). Pilote le titre, le sous-texte et le
    /// rendu de la 7ᵉ barre. Défaut `true` (rétro-compat des previews).
    var estEnCours: Bool = true
}

/// Style visuel de la carte. La variante `.gradient` reprend la teinte
/// du mesh du cercle en fond de carte, et passe textes / bulle / barres
/// en blanc avec glass effect.
enum StyleCarteScore: Sendable {
    case sobre
    case gradient
}

// MARK: - Vue principale

/// Carte « score du jour » — résumé glycémique de la journée en
/// cours (convention 06h-06h, recalculé en temps réel), style Apple
/// Santé : barre de titre avec icône + chevron, puis cercle dégradé
/// portant le chiffre, qualificatif court + heures de données, et
/// mini-graphique en barres des 7 derniers jours dont la dernière
/// est rendue en mode "en cours". Existe en deux variants visuels
/// (voir `StyleCarteScore`).
struct CarteScoreQuotidien: View {

    let contenu: ContenuCarteScore
    var style: StyleCarteScore = .sobre
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                ligneTitre
                ligneContenu
            }
            .padding(16)
            .background(fondCarte)
            .overlay(bordureCarte)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelleAccessibilite)
        .accessibilityHint("Ouvre les détails du score")
    }

    /// Barre de titre style Apple Santé : icône tintée + titre tinté
    /// dans la teinte du score (sobre) ou en blanc (gradient), chevron
    /// à droite.
    private var ligneTitre: some View {
        HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(couleurTitre)
            Text(contenu.estEnCours ? "Score du jour" : "Dernier score")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(couleurTitre)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(couleurChevron)
        }
    }

    private var ligneContenu: some View {
        HStack(spacing: 14) {
            CercleScore(score: contenu.score, style: style)

            VStack(alignment: .leading, spacing: 2) {
                Text(libelleQualitatif)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(couleurTexte)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(libelleSousTexte)
                    .font(.caption)
                    .foregroundStyle(couleurSubtext)
            }

            Spacer(minLength: 8)

            BarresHistorique(
                historique: contenu.historique,
                scoreActuel: contenu.score,
                pourcentageJourActuel: contenu.heuresJourEcoulees / 24,
                estEnCours: contenu.estEnCours,
                style: style
            )
            .accessibilityHidden(true)
        }
    }

    /// Sous-texte sous le qualificatif : « Xh de données » pour le jour en
    /// cours, sinon la date du jour complet affiché (« Hier », « Samedi 20 juin »).
    private var libelleSousTexte: String {
        guard contenu.estEnCours else { return libelleDateComplete }
        let heures = Int(contenu.heuresJourEcoulees.rounded(.down))
        return "\(heures)h de données"
    }

    /// Date relative du jour complet affiché (mode bascule sur la veille).
    private var libelleDateComplete: String {
        if Calendar.current.isDateInYesterday(contenu.date) { return "Hier" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        let s = f.string(from: contenu.date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Couleur du sous-texte : blanc à 70 % d'opacité en gradient,
    /// `.secondary` standard en sobre.
    private var couleurSubtext: Color {
        switch style {
        case .sobre:    return .secondary
        case .gradient: return Color.white.opacity(0.7)
        }
    }

    // MARK: Apparence dérivée du style

    @ViewBuilder
    private var fondCarte: some View {
        switch style {
        case .sobre:
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        case .gradient:
            TimelineView(.animation) { contexte in
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(MeshScore.gradient(
                        pour: contenu.score,
                        phase: MeshScore.phase(date: contexte.date)
                    ))
            }
        }
    }

    @ViewBuilder
    private var bordureCarte: some View {
        switch style {
        case .sobre:
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        case .gradient:
            // Pas de bordure : le mesh fournit déjà la délimitation visuelle.
            EmptyView()
        }
    }

    private var couleurTitre: Color {
        switch style {
        case .sobre:
            guard let score = contenu.score else { return .secondary }
            return CouleurScore.couleur(pour: score)
        case .gradient:
            return .white
        }
    }

    private var couleurTexte: Color {
        switch style {
        case .sobre:    return .primary
        case .gradient: return .white
        }
    }

    private var couleurChevron: Color {
        switch style {
        case .sobre:    return Color(.tertiaryLabel)
        case .gradient: return Color.white.opacity(0.75)
        }
    }

    /// Libellé qualitatif court affiché à droite du cercle. 5 paliers
    /// alignés sur les seuils visuels du projet.
    private var libelleQualitatif: String {
        guard let score = contenu.score else { return "Indisponible" }
        switch score {
        case 90...:    return "Très bonne"
        case 70..<90:  return "Bonne"
        case 50..<70:  return "Moyenne"
        case 30..<50:  return "Difficile"
        default:       return "Très difficile"
        }
    }

    private var libelleAccessibilite: String {
        let heures = Int(contenu.heuresJourEcoulees.rounded(.down))
        if let score = contenu.score {
            return "Score du jour : \(score) sur 100, \(heures) heures de données, journée \(libelleQualitatif.lowercased())"
        }
        return "Score du jour indisponible, \(heures) heures de données"
    }
}

// MARK: - Couleur d'accent du score

/// Teinte continue alignée sur le mesh gradient : `hue` croît
/// linéairement de 0 (rouge, score 0) à 0.33 (vert, score 100). Le titre,
/// la dernière barre de l'historique et l'ombre du cercle (variante
/// sobre) utilisent tous cette même teinte pour rester raccord.
///
/// Internal (pas private) parce que d'autres composants du module
/// (ex. `DetailScoreVue`) en dépendent pour rester visuellement
/// cohérents avec la carte.
enum CouleurScore {
    static func hue(pour score: Int) -> Double {
        let borne = Double(min(100, max(0, score)))
        return (borne / 100.0) * 0.33
    }

    /// Couleur pleine d'accent — saturation/brightness calibrées pour
    /// rester lisibles en petit (titre 15pt, barre 5pt de large).
    static func couleur(pour score: Int) -> Color {
        Color(hue: hue(pour: score), saturation: 0.85, brightness: 0.80)
    }
}

// MARK: - Mesh gradient partagé

/// Constructeur du `MeshGradient` partagé entre :
///   - le cercle de la variante sobre (où il remplit la bulle)
///   - le fond de carte de la variante gradient (où il remplit la carte)
///
/// Centralisé ici pour garantir une cohérence parfaite entre les deux
/// usages — si on retouche les couleurs ou les points, les deux suivent.
///
/// Internal (pas private) parce que `DetailScoreVue` réutilise le
/// même gradient pour son cercle 100pt.
enum MeshScore {

    /// Période de la boucle d'animation, en secondes. La motion est
    /// composée de plusieurs cycles (orbites Lissajous des points + onde
    /// chromatique traversant le mesh) ; cette période est la base que
    /// les fréquences individuelles multiplient.
    static let dureeBoucle: Double = 7.0

    /// Convertit une date en phase angulaire (en radians) pour alimenter
    /// l'orbite des points intérieurs et l'onde chromatique. À appeler
    /// depuis un `TimelineView(.animation)` pour rester synchro avec le
    /// refresh rate de l'écran.
    ///
    /// **Pas de wrap** : on laisse la phase croître indéfiniment, les
    /// fonctions trig gèrent la périodicité d'elles-mêmes. Wrapper à 2π
    /// créerait des sauts visibles puisque les fréquences (0.5, 0.8, 1.3,
    /// ...) ne sont pas des multiples entiers de la période de base —
    /// au moment du wrap, `cos(freq · 2π)` ne vaudrait pas `cos(0)`.
    /// La précision Double absorbe sans problème les ~10⁹ secondes
    /// depuis la date de référence.
    static func phase(date: Date) -> Double {
        date.timeIntervalSinceReferenceDate / dureeBoucle * 2 * .pi
    }

    /// Mesh 4×4 (16 points). Le passage de 3×3 à 4×4 double la densité
    /// d'interpolation : chaque transition coin↔centre traverse un
    /// point intermédiaire, ce qui élimine les "spots" sombres visibles
    /// dans la grille 3×3 et permet aux courants chaud/froid de dessiner
    /// de vraies courbes plutôt que des transitions rectilignes.
    ///
    /// **Périmètre figé / intérieur animé** : les 12 points du périmètre
    /// (indices 0-3, 4, 7, 8, 11, 12-15) restent strictement sur les
    /// bords (y=0/1, x=0/1) — c'est ce qui garantit que la silhouette
    /// de la rounded-rect / du cercle ne se déforme pas. Seuls les
    /// **4 points intérieurs** (indices 5, 6, 9, 10) bougent.
    ///
    /// Chaque point intérieur trace une **Lissajous** : fréquences X et Y
    /// distinctes (et différentes d'un point à l'autre) → les orbites ne
    /// se referment pas sur elles-mêmes et les 4 points dérivent en/hors
    /// de phase indéfiniment. Plus de symétrie rotationnelle perceptible,
    /// la motion paraît organique au lieu de "roue qui tourne".
    static func points(phase p: Double = 0) -> [SIMD2<Float>] {
        // Amplitudes serrées sur l'horizontal (motion visible) et la
        // verticale (gap minimal 0.08 entre rangées 1/2 garanti).
        let ampX: Float = 0.09
        let ampY: Float = 0.05
        let t = Float(p)
        func lissajous(
            _ base: SIMD2<Float>,
            _ freqX: Float,
            _ freqY: Float,
            _ dephasage: Float
        ) -> SIMD2<Float> {
            SIMD2(
                base.x + ampX * cos(freqX * t + dephasage),
                base.y + ampY * sin(freqY * t + dephasage)
            )
        }
        return [
            // Rangée 0 (haut) — y = 0 strict
            SIMD2(0.00, 0.00), SIMD2(0.33, 0.00), SIMD2(0.67, 0.00), SIMD2(1.00, 0.00),
            // Rangée 1 — bords figés, intérieurs en Lissajous distinctes
            SIMD2(0.00, 0.32),
                lissajous(SIMD2(0.40, 0.42), 1.0, 1.3, 0),
                lissajous(SIMD2(0.60, 0.30), 0.8, 1.1, .pi / 2),
                SIMD2(1.00, 0.36),
            // Rangée 2 — bords figés, intérieurs en Lissajous distinctes
            SIMD2(0.00, 0.64),
                lissajous(SIMD2(0.30, 0.62), 1.2, 0.9, .pi),
                lissajous(SIMD2(0.70, 0.72), 0.9, 1.4, 3 * .pi / 2),
                SIMD2(1.00, 0.68),
            // Rangée 3 (bas) — y = 1 strict
            SIMD2(0.00, 1.00), SIMD2(0.33, 1.00), SIMD2(0.67, 1.00), SIMD2(1.00, 1.00),
        ]
    }

    static func gradient(pour score: Int?, phase: Double = 0) -> MeshGradient {
        let pts = points(phase: phase)
        guard let score else {
            return MeshGradient(
                width: 4,
                height: 4,
                points: pts,
                colors: nuancesGrises,
                colorSpace: .perceptual
            )
        }
        let teinte = CouleurScore.hue(pour: score)
        return MeshGradient(
            width: 4,
            height: 4,
            points: pts,
            colors: colors(hue: teinte, phase: phase),
            colorSpace: .perceptual
        )
    }

    /// 16 stops organisés en **X chaud/froid** + **onde diagonale animée** :
    ///
    ///   - **Base statique** : coins TL/BR chauds (`+0.028`), coins TR/BL
    ///     froids (`-0.028`). Les intérieurs ont un offset réduit (`±0.003`)
    ///     pour éviter la "boundary" nette qui apparaissait avec ±0.014 :
    ///     le centre n'est plus polarisé, seuls les coins portent une
    ///     signature chromatique forte.
    ///   - **Onde traveling** : une sinusoïde traverse le mesh en
    ///     diagonale TL→BR avec une période deux fois plus lente que les
    ///     orbites des points. Chaque stop voit sa hue glisser dans le
    ///     temps — les courants chaud/froid coulent au lieu de tourner
    ///     en rond.
    ///
    /// **Brightness resserrée** dans [0.80, 0.88] — Δ0.08 au lieu du
    /// Δ0.29 de la version 3×3, qui plaquait des taches sombres aux
    /// coins. Le texte blanc reste lisible grâce à la saturation
    /// élevée + ombre portée.
    private static func colors(hue h: Double, phase p: Double = 0) -> [Color] {
        // Base statique : coins fortement marqués, intérieurs presque
        // neutres → le X chaud/froid n'a plus de frontière nette au centre.
        let dhStatic: [Double] = [
            +0.028, +0.006, -0.006, -0.028,
            +0.018, +0.003, -0.003, -0.018,
            -0.018, -0.003, +0.003, +0.018,
            -0.028, -0.006, +0.006, +0.028,
        ]
        // Onde diagonale animée — fréquence 0.5× les orbites des points
        // pour créer des cycles de drift décorrélés de la motion géométrique.
        let dhWaveAmp: Double = 0.012
        let dhWave: [Double] = (0..<16).map { i in
            let col = Double(i % 4) / 3.0
            let row = Double(i / 4) / 3.0
            return dhWaveAmp * sin(0.5 * p + (col + row) * .pi)
        }
        let dh: [Double] = (0..<16).map { dhStatic[$0] + dhWave[$0] }
        // Saturation — coins légèrement plus saturés que le centre pour
        // garder de la profondeur chromatique sans noircir.
        let saturations: [Double] = [
            0.88, 0.86, 0.86, 0.88,
            0.86, 0.84, 0.84, 0.86,
            0.86, 0.84, 0.84, 0.86,
            0.88, 0.86, 0.86, 0.88,
        ]
        // Brightness resserrée [0.80, 0.88] — fini les coins sombres,
        // le mesh reste lumineux et homogène, et le texte blanc tient.
        let brightnesses: [Double] = [
            0.80, 0.82, 0.82, 0.80,
            0.82, 0.88, 0.88, 0.82,
            0.82, 0.88, 0.88, 0.82,
            0.80, 0.82, 0.82, 0.80,
        ]
        return (0..<16).map { i in
            Color(
                hue: hueWrap(h + dh[i]),
                saturation: saturations[i],
                brightness: brightnesses[i]
            )
        }
    }

    /// Replie une hue éventuellement négative ou > 1 dans [0, 1).
    private static func hueWrap(_ h: Double) -> Double {
        let v = h.truncatingRemainder(dividingBy: 1.0)
        return v < 0 ? v + 1.0 : v
    }

    /// Variantes de gris pour le cas `score == nil` — même structure
    /// que `colors(hue:)` : highlight central léger, coins moins sombres
    /// qu'en 3×3 pour rester cohérent avec le mesh coloré. 16 stops.
    private static let nuancesGrises: [Color] = [
        Color(white: 0.72), Color(white: 0.78), Color(white: 0.78), Color(white: 0.72),
        Color(white: 0.78), Color(white: 0.90), Color(white: 0.90), Color(white: 0.78),
        Color(white: 0.78), Color(white: 0.90), Color(white: 0.90), Color(white: 0.78),
        Color(white: 0.72), Color(white: 0.78), Color(white: 0.78), Color(white: 0.72),
    ]
}

// MARK: - Bulle du score

/// Cercle portant le chiffre du score. Deux rendus selon le `style` :
///   - **sobre** : mesh gradient interne + ombre douce + score blanc.
///   - **gradient** : glass effect (la carte porte déjà le mesh) + score
///     blanc, sans ombre (la carte fait office d'arrière-plan coloré).
private struct CercleScore: View {
    let score: Int?
    let style: StyleCarteScore

    private static let taille: CGFloat = 56

    var body: some View {
        ZStack {
            if let score {
                contenu(score: score)
            } else {
                contenuIndisponible
            }
        }
    }

    @ViewBuilder
    private func contenu(score: Int) -> some View {
        switch style {
        case .sobre:
            TimelineView(.animation) { contexte in
                MeshScore.gradient(
                    pour: score,
                    phase: MeshScore.phase(date: contexte.date)
                )
                .clipShape(Circle())
                .frame(width: Self.taille, height: Self.taille)
                .shadow(
                    color: CouleurScore.couleur(pour: score).opacity(0.35),
                    radius: 6,
                    x: 0,
                    y: 3
                )
            }

            texteScore(score)
                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)

        case .gradient:
            Text("\(score)")
                .font(Self.policeGrosScore)
                .foregroundStyle(.white)
                .monospacedDigit()
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
        }
    }

    private static let policeGrosScore = Font.system(size: 42, weight: .heavy, design: .rounded)

    private func texteScore(_ score: Int) -> some View {
        Text("\(score)")
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
    }

    @ViewBuilder
    private var contenuIndisponible: some View {
        switch style {
        case .sobre:
            Circle().fill(Color.secondary.opacity(0.18))
                .frame(width: Self.taille, height: Self.taille)
            Text("—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
        case .gradient:
            Text("—")
                .font(Self.policeGrosScore)
                .foregroundStyle(.white.opacity(0.6))
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
        }
    }
}

// MARK: - Mini-histogramme 7 jours (composé à la main)

/// Mini bar chart maison — 6 barres consolidées + 1 barre "en cours"
/// pour le jour courant. Composé à la main (HStack de rectangles)
/// plutôt que via Swift Charts parce que la barre du jour nécessite :
///   - un remplissage partiel proportionnel au % de la journée écoulée
///   - une bordure pointillée pulsante
///   - une animation continue de l'opacité de la bordure
///
/// Trois éléments que `BarMark` ne sait pas composer directement.
private struct BarresHistorique: View {
    let historique: [Int?]
    let scoreActuel: Int?
    /// 0…1, % de la journée écoulée depuis 06h (pilote le remplissage
    /// partiel de la 7ᵉ barre). À midi : ~0.25. À minuit : 0.75.
    let pourcentageJourActuel: Double
    /// `true` → la dernière barre est rendue « en cours » (partielle) ; sinon
    /// toutes les barres sont consolidées (mode jour complet).
    var estEnCours: Bool = true
    let style: StyleCarteScore

    /// Largeur d'une barre, partagée par toutes (régulières et en cours).
    private static let largeurBarre: CGFloat = 5

    /// Spacing entre barres dans le HStack — calé pour qu'un total
    /// de 7 barres × 5pt + 6 gaps × 4pt = 59pt rentre confortablement
    /// dans la largeur historique de ~64pt.
    private static let spacing: CGFloat = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            ForEach(0..<historique.count, id: \.self) { index in
                barre(at: index)
                    .frame(width: Self.largeurBarre)
            }
        }
        .frame(width: 64, height: 44)
    }

    @ViewBuilder
    private func barre(at index: Int) -> some View {
        if estJourCourant(index) {
            BarreEnCours(
                valeur: historique[index],
                pourcentageJour: pourcentageJourActuel,
                style: style
            )
        } else {
            BarreHistorique(valeur: historique[index], style: style)
        }
    }

    private func estJourCourant(_ index: Int) -> Bool {
        estEnCours && index == historique.count - 1
    }
}

// MARK: - Barre régulière (jours J-6 … J-1)

/// Barre consolidée d'un jour passé — simple rectangle arrondi à la
/// couleur de la palette, hauteur proportionnelle au score. Valeur
/// `nil` → barre pleine hauteur, opacité réduite (« fantôme »).
private struct BarreHistorique: View {
    let valeur: Int?
    let style: StyleCarteScore

    var body: some View {
        GeometryReader { geo in
            let fraction = Self.fractionHauteur(valeur)
            let hauteur = geo.size.height * fraction
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(couleur)
                    .frame(height: hauteur)
            }
        }
    }

    /// Plancher visuel à 3 % — un score très bas (1–2) doit rester
    /// perceptible. `nil` (pas de donnée) → barre pleine hauteur en
    /// teinte fantôme.
    private static func fractionHauteur(_ v: Int?) -> Double {
        guard let v else { return 1.0 }
        return Double(max(3, min(100, v))) / 100.0
    }

    private var couleur: Color {
        switch style {
        case .sobre:
            return valeur == nil
                ? Color.secondary.opacity(0.18)
                : Color.secondary.opacity(0.5)
        case .gradient:
            return valeur == nil
                ? Color.white.opacity(0.15)
                : Color.white.opacity(0.45)
        }
    }
}

// MARK: - Barre du jour en cours

/// 7ᵉ barre — même apparence générale que les barres consolidées
/// (couleur du score sur fond fantôme), avec **un seul** indice
/// visuel pour signaler "en construction" :
///
///   - hauteur totale identique aux autres barres (= celle qui
///     correspondrait au score actuel)
///   - **fond fantôme** sur toute cette hauteur (opacité 0.3) —
///     matérialise la cible que la barre va atteindre
///   - **remplissage plein** depuis le bas, proportionnel au % de
///     la journée écoulée (à midi, ~25 % rempli ; à minuit, ~75 %)
///
/// Pas de bordure ni d'animation pulse — le seul fait que la barre
/// "monte" au fil de la journée suffit à la différencier des autres.
private struct BarreEnCours: View {
    let valeur: Int?
    /// 0…1, fraction de la barre remplie depuis le bas.
    let pourcentageJour: Double
    let style: StyleCarteScore

    var body: some View {
        GeometryReader { geo in
            let fraction = Self.fractionHauteur(valeur)
            let hauteurBarre = geo.size.height * fraction
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    // Fond fantôme — opacité 0.3 sur toute la hauteur
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(couleurAccent.opacity(0.3))

                    // Remplissage proportionnel au % journée écoulée
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(couleurAccent)
                        .frame(height: hauteurBarre * pourcentageJour)
                }
                .frame(height: hauteurBarre)
            }
        }
    }

    /// Même règle que `BarreHistorique` — plancher à 3 % pour rester
    /// visible, `nil` → pleine hauteur.
    private static func fractionHauteur(_ v: Int?) -> Double {
        guard let v else { return 1.0 }
        return Double(max(3, min(100, v))) / 100.0
    }

    /// Teinte du jour : palette score (sobre) ou blanc (gradient).
    /// Pour `nil`, on tombe en gris neutre — la pulsation reste mais
    /// la barre n'a pas de couleur propre.
    private var couleurAccent: Color {
        switch style {
        case .sobre:
            guard let v = valeur else { return Color.secondary.opacity(0.5) }
            return CouleurScore.couleur(pour: v)
        case .gradient:
            return .white
        }
    }
}

// MARK: - Aperçus

/// Wrapper de preview avec deux sliders : score (0–100) et heures de
/// la journée (0–24). Permet d'observer le rendu pour différents
/// moments de la journée — matin (peu de remplissage de la 7ᵉ barre),
/// midi (1/4), soir (3/4).
private struct ApercuAvecSlider: View {
    @State private var score: Double = 78
    @State private var heures: Double = 8

    var body: some View {
        let contenu = ContenuCarteScore(
            score: Int(score),
            date: Date(),
            historique: [65, 78, 71, 55, 88, 73, Int(score)],
            heuresJourEcoulees: heures
        )
        VStack(spacing: 20) {
            Spacer()

            CarteScoreQuotidien(contenu: contenu, style: .sobre, onTap: {})
            CarteScoreQuotidien(contenu: contenu, style: .gradient, onTap: {})

            VStack(spacing: 6) {
                Slider(value: $score, in: 0...100, step: 1)
                HStack {
                    Text("0")
                    Spacer()
                    Text("\(Int(score)) / 100")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("100")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Slider(value: $heures, in: 0...24, step: 0.5)
                HStack {
                    Text("0h")
                    Spacer()
                    Text("\(heures, specifier: "%.1f")h depuis 06h")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("24h")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Slider de score") {
    ApercuAvecSlider()
}

#Preview("Slider de score — sombre") {
    ApercuAvecSlider()
        .preferredColorScheme(.dark)
}

#Preview("Score du jour - Matin 8h") {
    let contenu = ContenuCarteScore(
        score: 85,
        date: Date(),
        historique: [65, 78, 71, 55, 88, 73, 85],
        heuresJourEcoulees: 2
    )
    VStack(spacing: 16) {
        Spacer()
        CarteScoreQuotidien(contenu: contenu, style: .sobre, onTap: {})
        CarteScoreQuotidien(contenu: contenu, style: .gradient, onTap: {})
        Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}

#Preview("Score du jour - Midi") {
    let contenu = ContenuCarteScore(
        score: 78,
        date: Date(),
        historique: [65, 78, 71, 55, 88, 73, 78],
        heuresJourEcoulees: 8
    )
    VStack(spacing: 16) {
        Spacer()
        CarteScoreQuotidien(contenu: contenu, style: .sobre, onTap: {})
        CarteScoreQuotidien(contenu: contenu, style: .gradient, onTap: {})
        Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}

#Preview("Score du jour - Soir") {
    let contenu = ContenuCarteScore(
        score: 72,
        date: Date(),
        historique: [65, 78, 71, 55, 88, 73, 72],
        heuresJourEcoulees: 16
    )
    VStack(spacing: 16) {
        Spacer()
        CarteScoreQuotidien(contenu: contenu, style: .sobre, onTap: {})
        CarteScoreQuotidien(contenu: contenu, style: .gradient, onTap: {})
        Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}

#Preview("Score indisponible") {
    let contenu = ContenuCarteScore(
        score: nil,
        date: Date(),
        historique: [60, nil, 72, 58, nil, 65, nil],
        heuresJourEcoulees: 2
    )
    VStack(spacing: 16) {
        Spacer()
        CarteScoreQuotidien(contenu: contenu, style: .sobre, onTap: {})
        CarteScoreQuotidien(contenu: contenu, style: .gradient, onTap: {})
        Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
