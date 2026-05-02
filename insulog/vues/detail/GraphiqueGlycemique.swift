//
//  GraphiqueGlycemique.swift
//  insulog
//
//  Created by Alexandre on 02/05/2026.
//

import Charts
import SwiftUI

// MARK: - GraphiqueGlycemique
//
// Composant unifié remplaçant les anciens `GraphiqueGlycemiqueRepas` et
// `GraphiqueGlycemiqueSport`. Le rendu visuel et la logique de marqueurs
// (T0/pic, début/fin, hypo) étaient quasi-identiques entre les deux —
// les seules différences sont la fenêtre temporelle, les marqueurs
// sémantiques, et la zone d'activité (sport uniquement).
//
// On factorise tout dans une `Configuration` immutable. Les call-sites
// passent par les factories `pourRepas(...)` et `pourSport(...)` qui
// construisent la `Configuration` adéquate à partir des modèles métier
// (`EtatAnalyse` côté repas, `EtatMiniCourbeSport` côté sport).
//
// Cas dégradés (`enAttente`, `donneesManquantes`, `sansAnalyse`)
// partagent désormais un seul `EtatIndisponibleGraphique` — plus de
// duplication entre les deux pages détail.
struct GraphiqueGlycemique: View {

    let etat: Etat

    private static let hauteur: CGFloat = 220

    var body: some View {
        Group {
            switch etat {
            case .disponible(let config):
                CourbeDisponible(config: config)
            case .enAttente(let minutes, let description):
                EtatIndisponibleGraphique(
                    icone: "clock.fill",
                    titre: "Analyse disponible dans \(formatDelaiAttente(minutes))",
                    description: description
                )
            case .donneesManquantes(let description):
                EtatIndisponibleGraphique(
                    icone: "exclamationmark.triangle",
                    titre: "Données CGM insuffisantes",
                    description: description
                )
            case .sansAnalyse(let titre, let description):
                EtatIndisponibleGraphique(
                    icone: "syringe",
                    titre: titre,
                    description: description
                )
            }
        }
        .frame(height: Self.hauteur)
    }
}

// MARK: - Etat
//
// Quatre cas exclusifs. La séparation `donneesManquantes` /
// `sansAnalyse` permet d'utiliser des messages différents selon la
// raison (CGM HS vs repas sans bolus) sans fusionner les sémantiques.
extension GraphiqueGlycemique {

    enum Etat {
        case disponible(Configuration)
        case enAttente(minutesRestantes: Int, description: String)
        case donneesManquantes(description: String)
        case sansAnalyse(titre: String, description: String)
    }
}

// MARK: - Configuration
//
// Tout ce qu'il faut pour rendre une courbe : axes, couleur, marqueurs,
// éventuelle zone d'activité. Construite par les factories et passée
// telle quelle à la sous-vue `CourbeDisponible`.
extension GraphiqueGlycemique {

    struct Configuration {
        let header: String
        let pointsCourbe: [PointCourbe]
        let couleurCourbe: Color

        let domaineX: ClosedRange<TimeInterval>
        let xMarques: [TimeInterval]
        let formatLabelTemps: (TimeInterval) -> String

        let domaineY: ClosedRange<Double>
        let yMarques: [Double]

        /// Bandeau bleu très transparent sur la fenêtre d'effort —
        /// uniquement pour la page Sport. `nil` côté repas.
        let zoneActivite: ClosedRange<TimeInterval>?

        let marqueurs: [Marqueur]
    }

    /// Échantillon de courbe — type unifié qui agrège un instant et
    /// une glycémie. Évite de dépendre de `PointCgm` ou `PointCgmSport`
    /// à l'intérieur du composant graphique.
    struct PointCourbe: Identifiable, Hashable {
        let id = UUID()
        let temps: TimeInterval
        let valeur: Double
    }

    /// Marqueur ponctuel sur la courbe (T0, pic, début, fin, hypo).
    /// Le `label` est optionnel et peut être positionné en haut ou
    /// en bas du point — l'hypo est en bas pour ne pas chevaucher
    /// les autres marqueurs (généralement positionnés en haut).
    struct Marqueur: Identifiable {
        let id = UUID()
        let temps: TimeInterval
        let valeur: Double
        let couleur: Color
        let style: Style
        let label: Label?

        enum Style {
            /// Cercle ouvert (juste un contour). Utilisé pour les
            /// repères neutres (T0, début) — pas le focus visuel.
            case cercleOuvert
            /// Cercle plein. Taille personnalisable parce que le pic
            /// (60-80) doit ressortir plus que les marqueurs latéraux.
            case cerclePlein(taille: CGFloat)
        }

        struct Label {
            /// Texte multilignes possible (séparateur `\n`) — utilisé
            /// pour empiler par exemple « Début » et « 130 » sur la
            /// même annotation.
            let texte: String
            let position: Position
            let alignement: HorizontalAlignment

            enum Position {
                case haut
                case bas
            }
        }
    }
}

// MARK: - CourbeDisponible
//
// Sous-vue dédiée au rendu Swift Charts. Extraction motivée par les
// mêmes raisons que dans les anciens composants : alléger le `body`
// parent et accélérer le type-checking SwiftUI sur les marks empilés.
private struct CourbeDisponible: View {

    let config: GraphiqueGlycemique.Configuration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            entete
            chart
        }
    }

    private var entete: some View {
        Text(config.header)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        Chart {
            zoneCible
            zoneActivite
            ligneHypo
            ligneHyper
            courbe
            marqueursContent
        }
        .chartXScale(domain: config.domaineX)
        .chartYScale(domain: config.domaineY)
        .chartXAxis { axeXContent }
        .chartYAxis { axeYContent }
        .chartPlotStyle { plot in
            plot.padding(.vertical, 16)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(config.header))
    }

    // MARK: - Zones de fond

    /// Bande verte transparente sur la cible 70-180 mg/dL.
    @ChartContentBuilder
    private var zoneCible: some ChartContent {
        RectangleMark(
            xStart: .value("Début", config.domaineX.lowerBound),
            xEnd: .value("Fin", config.domaineX.upperBound),
            yStart: .value("Cible bas", 70),
            yEnd: .value("Cible haut", 180)
        )
        .foregroundStyle(.green.opacity(0.08))
    }

    /// Bandeau bleu sur la fenêtre d'effort — sport uniquement.
    @ChartContentBuilder
    private var zoneActivite: some ChartContent {
        if let plage = config.zoneActivite {
            RectangleMark(
                xStart: .value("Début effort", plage.lowerBound),
                xEnd: .value("Fin effort", plage.upperBound),
                yStart: .value("Y bas", config.domaineY.lowerBound),
                yEnd: .value("Y haut", config.domaineY.upperBound)
            )
            .foregroundStyle(.blue.opacity(0.06))
        }
    }

    // MARK: - Lignes de seuil

    @ChartContentBuilder
    private var ligneHypo: some ChartContent {
        RuleMark(y: .value("Hypo", 70))
            .foregroundStyle(.red.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    @ChartContentBuilder
    private var ligneHyper: some ChartContent {
        RuleMark(y: .value("Hyper", 180))
            .foregroundStyle(.orange.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    // MARK: - Courbe principale

    @ChartContentBuilder
    private var courbe: some ChartContent {
        ForEach(pointsAffichables) { point in
            LineMark(
                x: .value("Temps", point.temps),
                y: .value("Glycémie", point.valeur)
            )
            .foregroundStyle(config.couleurCourbe)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
    }

    /// Points filtrés à la fenêtre affichée (avec une marge de 5min
    /// pour que l'interpolation reste fluide aux extrémités).
    private var pointsAffichables: [GraphiqueGlycemique.PointCourbe] {
        let marge: TimeInterval = 5 * 60
        let basse = config.domaineX.lowerBound - marge
        let haute = config.domaineX.upperBound + marge
        return config.pointsCourbe.filter { $0.temps >= basse && $0.temps <= haute }
    }

    // MARK: - Marqueurs

    @ChartContentBuilder
    private var marqueursContent: some ChartContent {
        ForEach(config.marqueurs) { marqueur in
            marqueurMark(marqueur)
        }
    }

    /// Construit un PointMark + son symbole + son annotation. Les
    /// trois cas (style ouvert / plein, label haut / bas / aucun)
    /// sont composés ici plutôt que d'éclater en sous-vues : le
    /// type `ChartContent` ne se compose pas aussi naturellement
    /// que `View`, donc on garde tout au même endroit.
    @ChartContentBuilder
    private func marqueurMark(
        _ m: GraphiqueGlycemique.Marqueur
    ) -> some ChartContent {
        switch m.style {
        case .cercleOuvert:
            PointMark(
                x: .value("Temps", m.temps),
                y: .value("Glycémie", m.valeur)
            )
            .symbol {
                Circle()
                    .strokeBorder(m.couleur, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            }
            .annotation(
                position: positionAnnotation(m.label),
                alignment: alignmentAnnotation(m.label),
                spacing: 4
            ) {
                texteAnnotation(m)
            }
        case .cerclePlein(let taille):
            PointMark(
                x: .value("Temps", m.temps),
                y: .value("Glycémie", m.valeur)
            )
            .symbol(.circle)
            .symbolSize(taille)
            .foregroundStyle(m.couleur)
            .annotation(
                position: positionAnnotation(m.label),
                alignment: alignmentAnnotation(m.label),
                spacing: 4
            ) {
                texteAnnotation(m)
            }
        }
    }

    @ViewBuilder
    private func texteAnnotation(_ m: GraphiqueGlycemique.Marqueur) -> some View {
        if let label = m.label {
            Text(label.texte)
                .font(.caption2.bold())
                .foregroundStyle(m.couleur)
                .multilineTextAlignment(.center)
                .monospacedDigit()
        }
    }

    private func positionAnnotation(
        _ label: GraphiqueGlycemique.Marqueur.Label?
    ) -> AnnotationPosition {
        switch label?.position {
        case .bas:    return .bottom
        case .haut:   return .top
        case .none:   return .top
        }
    }

    private func alignmentAnnotation(
        _ label: GraphiqueGlycemique.Marqueur.Label?
    ) -> Alignment {
        switch label?.alignement {
        case .leading:   return .leading
        case .trailing:  return .trailing
        case .none:      return .center
        default:         return .center
        }
    }

    // MARK: - Axes

    private var axeXContent: some AxisContent {
        AxisMarks(values: config.xMarques) { valeur in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let temps = valeur.as(TimeInterval.self) {
                    Text(config.formatLabelTemps(temps))
                        .font(.caption2)
                }
            }
        }
    }

    private var axeYContent: some AxisContent {
        AxisMarks(position: .trailing, values: config.yMarques) { valeur in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let v = valeur.as(Double.self) {
                    Text("\(Int(v))")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - EtatIndisponibleGraphique
//
// Vue partagée pour les états « non disponible » (en attente, données
// manquantes, sans analyse). Centralise icône + titre + description en
// pile centrée. Remplace les anciennes `EtatIndisponible` (repas) et
// `EtatIndisponibleSport` qui étaient identiques mot pour mot.
private struct EtatIndisponibleGraphique: View {

    let icone: String
    let titre: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icone)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(titre)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre). \(description)")
    }
}

// MARK: - Helpers de format

/// Format compact du délai d'attente : « 30min », « 1h », « 1h30 ».
private func formatDelaiAttente(_ minutes: Int) -> String {
    let m = max(0, minutes)
    if m < 60 { return "\(m)min" }
    let h = m / 60
    let r = m % 60
    return r == 0 ? "\(h)h" : "\(h)h\(r)"
}

// MARK: - Factory pour la page Repas

extension GraphiqueGlycemique {

    /// Construit le graphique adapté à un repas. Mappe l'`EtatAnalyse`
    /// métier sur l'état du composant et calcule la `Configuration`
    /// pour le cas `.disponible` (fenêtre T-30min → T+4h, marqueurs
    /// T0 + pic + hypo conditionnel).
    ///
    /// **Fenêtre T+4h** (et non T+3h comme l'ancienne version) : le
    /// pic se produit typiquement entre T+30min et T+1h30, mais les
    /// hypoglycémies post-bolus arrivent souvent entre T+3h et T+4h
    /// (durée d'action de l'analogue rapide). Couper à T+3h faisait
    /// disparaître l'hypo du graphique alors qu'elle existait dans
    /// les données — l'utilisateur voyait la courbe descendre sans
    /// pouvoir cliquer sur le creux.
    static func pourRepas(etat: EtatAnalyse) -> GraphiqueGlycemique {
        switch etat {
        case .disponible(let reponse):
            return GraphiqueGlycemique(
                etat: .disponible(.repas(reponse: reponse))
            )
        case .enAttente(let minutes):
            return GraphiqueGlycemique(
                etat: .enAttente(
                    minutesRestantes: minutes,
                    description: "La fenêtre T+4h n'est pas encore complète."
                )
            )
        case .donneesManquantes:
            return GraphiqueGlycemique(
                etat: .donneesManquantes(
                    description: "Pas assez de points pour analyser ce repas."
                )
            )
        case .sansInjection:
            return GraphiqueGlycemique(
                etat: .sansAnalyse(
                    titre: "Pas d'analyse glycémique",
                    description: "Repas sans insuline — pas de réponse à analyser."
                )
            )
        }
    }
}

extension GraphiqueGlycemique.Configuration {

    /// Plus bas point dans la fenêtre `[debut, fin]`, à condition
    /// d'être strictement sous 70 mg/dL. `nil` sinon — pas d'hypo
    /// détectée. Extrait en helper partagé pour servir aux deux
    /// configurations (repas et sport) ET pour aider le type-checker
    /// SwiftUI qui peinait sur `.filter().min()` chaîné en littéral.
    static func pointHypo(
        dans points: [GraphiqueGlycemique.PointCourbe],
        debut: TimeInterval,
        fin: TimeInterval
    ) -> GraphiqueGlycemique.PointCourbe? {
        let pointsFenetre = points.filter { point in
            point.temps >= debut && point.temps <= fin
        }
        guard let pointMin = pointsFenetre.min(by: { $0.valeur < $1.valeur }),
              pointMin.valeur < 70 else {
            return nil
        }
        return pointMin
    }

    /// Configuration Repas : fenêtre T-30min → T+4h, axes verticaux
    /// sur les seuils cliniques 70/100/140/180/240, marqueurs T0 + pic
    /// + hypo conditionnel.
    static func repas(reponse: ReponseGlycemique) -> Self {
        let debut: TimeInterval = -30 * 60
        let fin: TimeInterval = 4 * 3600

        let pointsCourbe = reponse.pointsCgm.map {
            GraphiqueGlycemique.PointCourbe(
                temps: $0.secondesDepuisRepas,
                valeur: $0.valeur
            )
        }

        var marqueurs: [GraphiqueGlycemique.Marqueur] = []

        // Marqueur T0 — cercle ouvert gris, label « T0 » au-dessus.
        let valeurT0 = pointsCourbe
            .min(by: { abs($0.temps) < abs($1.temps) })?
            .valeur ?? reponse.valeurPic
        marqueurs.append(
            .init(
                temps: 0,
                valeur: valeurT0,
                couleur: .secondary,
                style: .cercleOuvert,
                label: .init(texte: "T0", position: .haut, alignement: .center)
            )
        )

        // Marqueur Pic — cercle plein dans la couleur du verdict, valeur au-dessus.
        marqueurs.append(
            .init(
                temps: reponse.tempsPic,
                valeur: reponse.valeurPic,
                couleur: reponse.verdict.couleur,
                style: .cerclePlein(taille: 80),
                label: .init(
                    texte: "\(Int(reponse.valeurPic))",
                    position: .haut,
                    alignement: .center
                )
            )
        )

        // Marqueur Hypo — uniquement si la courbe descend strictement
        // sous 70 mg/dL dans la fenêtre affichée. Cercle rouge plein,
        // valeur en bas pour ne pas chevaucher T0/pic.
        if let hypo = Self.pointHypo(dans: pointsCourbe, debut: debut, fin: fin) {
            marqueurs.append(
                .init(
                    temps: hypo.temps,
                    valeur: hypo.valeur,
                    couleur: .red,
                    style: .cerclePlein(taille: 60),
                    label: .init(
                        texte: "\(Int(hypo.valeur))",
                        position: .bas,
                        alignement: .center
                    )
                )
            )
        }

        return Self(
            header: "Réponse glycémique",
            pointsCourbe: pointsCourbe,
            couleurCourbe: reponse.verdict.couleur,
            domaineX: debut...fin,
            xMarques: Self.marquesTempsRepas(debut: debut, fin: fin),
            formatLabelTemps: Self.libelleTempsRepas,
            domaineY: 50...280,
            yMarques: [70, 100, 140, 180, 240],
            zoneActivite: nil,
            marqueurs: marqueurs
        )
    }

    /// Marques de l'axe X côté repas : T-30min, T0, T+1h, T+2h, T+3h, T+4h.
    /// Espacement 1h (et non 30min) pour rester lisible — sur 4h30
    /// d'amplitude, les labels « T+1h30 » se chevauchaient.
    private static func marquesTempsRepas(
        debut: TimeInterval,
        fin: TimeInterval
    ) -> [TimeInterval] {
        var valeurs: [TimeInterval] = [debut, 0]
        var t: TimeInterval = 3600
        while t <= fin {
            valeurs.append(t)
            t += 3600
        }
        return valeurs
    }

    /// Format français pour l'axe X côté repas : « T-30min », « T0 »,
    /// « T+1h », « T+2h ».
    private static func libelleTempsRepas(_ secondes: TimeInterval) -> String {
        let minutes = Int(secondes / 60)
        if minutes == 0 { return "T0" }
        let signe = minutes > 0 ? "+" : "-"
        let absMin = abs(minutes)
        if absMin < 60 { return "T\(signe)\(absMin)min" }
        let h = absMin / 60
        let m = absMin % 60
        return m == 0 ? "T\(signe)\(h)h" : "T\(signe)\(h)h\(m)"
    }
}

// MARK: - Factory pour la page Sport

extension GraphiqueGlycemique {

    /// Construit le graphique adapté à une activité sportive. Mappe
    /// l'`EtatMiniCourbeSport` sur l'état du composant et calcule la
    /// `Configuration` pour le cas `.disponible` (fenêtre T-30min →
    /// T+durée+30min, marqueurs début + fin + hypo conditionnel,
    /// bandeau bleu sur la fenêtre d'effort).
    static func pourSport(
        etat: EtatMiniCourbeSport,
        dureeMinutes: Int
    ) -> GraphiqueGlycemique {
        switch etat {
        case .disponible(let reponse):
            return GraphiqueGlycemique(
                etat: .disponible(.sport(reponse: reponse, dureeMinutes: dureeMinutes))
            )
        case .enAttente(let minutes):
            return GraphiqueGlycemique(
                etat: .enAttente(
                    minutesRestantes: minutes,
                    description: "La fenêtre post-effort n'est pas encore complète."
                )
            )
        case .donneesManquantes:
            return GraphiqueGlycemique(
                etat: .donneesManquantes(
                    description: "Pas assez de points pour analyser cette séance."
                )
            )
        }
    }
}

extension GraphiqueGlycemique.Configuration {

    /// Configuration Sport : fenêtre T-30min → T+durée+30min, axes
    /// verticaux 70/100/140/180, marqueurs début/fin (couleur verdict)
    /// + hypo conditionnel + bandeau bleu d'activité.
    static func sport(
        reponse: ReponseGlycemiqueSport,
        dureeMinutes: Int
    ) -> Self {
        let dureeSec = TimeInterval(dureeMinutes * 60)
        let debut: TimeInterval = -30 * 60
        let fin: TimeInterval = dureeSec + 30 * 60

        // Couleur du verdict — même logique que `MiniCourbeSport` pour
        // cohérence visuelle entre la liste et le détail.
        let couleurVerdict: Color = {
            if reponse.glycemieFin < 70 { return .red }
            if abs(reponse.deltaMgDl) < 20 { return .green }
            if reponse.deltaMgDl < -40 { return .orange }
            return .blue
        }()

        let pointsCourbe = reponse.pointsCgm.map {
            GraphiqueGlycemique.PointCourbe(
                temps: $0.secondesDepuisDebut,
                valeur: $0.valeur
            )
        }

        var marqueurs: [GraphiqueGlycemique.Marqueur] = []

        // Marqueur Début — cercle ouvert gris, label « Début » + valeur
        // sur deux lignes au-dessus, aligné à gauche pour ne pas
        // déborder à gauche du cadre.
        marqueurs.append(
            .init(
                temps: 0,
                valeur: reponse.glycemieDebut,
                couleur: .secondary,
                style: .cercleOuvert,
                label: .init(
                    texte: "Début\n\(Int(reponse.glycemieDebut))",
                    position: .haut,
                    alignement: .leading
                )
            )
        )

        // Marqueur Fin — cercle plein, couleur verdict, label « Fin »
        // + valeur sur deux lignes, aligné à droite.
        marqueurs.append(
            .init(
                temps: dureeSec,
                valeur: reponse.glycemieFin,
                couleur: couleurVerdict,
                style: .cerclePlein(taille: 80),
                label: .init(
                    texte: "Fin\n\(Int(reponse.glycemieFin))",
                    position: .haut,
                    alignement: .trailing
                )
            )
        )

        // Marqueur Hypo — si le min strictement < 70 dans la fenêtre.
        if let hypo = Self.pointHypo(dans: pointsCourbe, debut: debut, fin: fin) {
            marqueurs.append(
                .init(
                    temps: hypo.temps,
                    valeur: hypo.valeur,
                    couleur: .red,
                    style: .cerclePlein(taille: 60),
                    label: .init(
                        texte: "\(Int(hypo.valeur))",
                        position: .bas,
                        alignement: .center
                    )
                )
            )
        }

        return Self(
            header: "Glycémie pendant l'activité",
            pointsCourbe: pointsCourbe,
            couleurCourbe: couleurVerdict,
            domaineX: debut...fin,
            xMarques: Self.marquesTempsSport(debut: debut, dureeSec: dureeSec, fin: fin),
            formatLabelTemps: Self.libelleTempsSport,
            domaineY: 50...220,
            yMarques: [70, 100, 140, 180],
            zoneActivite: 0...dureeSec,
            marqueurs: marqueurs
        )
    }

    /// Marques de l'axe X côté sport : début de fenêtre, T0, milieu
    /// effort, fin effort, fin de fenêtre. Déduplication pour les
    /// sessions très courtes (durée < 10min) où plusieurs marques
    /// retomberaient sur le même instant.
    private static func marquesTempsSport(
        debut: TimeInterval,
        dureeSec: TimeInterval,
        fin: TimeInterval
    ) -> [TimeInterval] {
        let valeurs: [TimeInterval] = [debut, 0, dureeSec / 2, dureeSec, fin]
        return Array(Set(valeurs)).sorted()
    }

    /// Format français pour l'axe X côté sport : « -30min », « T0 »,
    /// « +20min », « +1h ». Différent du repas (pas de « T » devant
    /// les valeurs positives) pour rester compact dans la fenêtre
    /// asymétrique [-30min, +durée+30min].
    private static func libelleTempsSport(_ secondes: TimeInterval) -> String {
        let minutes = Int(secondes / 60)
        if minutes == 0 { return "T0" }
        let signe = minutes > 0 ? "+" : "-"
        let absMin = abs(minutes)
        if absMin < 60 { return "\(signe)\(absMin)min" }
        let h = absMin / 60
        let m = absMin % 60
        return m == 0 ? "\(signe)\(h)h" : "\(signe)\(h)h\(m)"
    }
}

// MARK: - Aperçu

#Preview("Repas — bon") {
    GraphiqueGlycemique.pourRepas(etat: ReponseGlycemiqueServiceMock.cas(.bon))
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
}

#Preview("Repas — avec hypo") {
    // `hypoApresPic` : pic à 195 puis chute à 60 mg/dL à T+4h. Avec
    // la fenêtre étendue à T+4h, le creux est désormais capturé et
    // le marqueur rouge s'affiche en bas du graphique.
    GraphiqueGlycemique.pourRepas(etat: ReponseGlycemiqueServiceMock.cas(.hypoApresPic))
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
}

#Preview("Repas — en attente") {
    GraphiqueGlycemique.pourRepas(etat: ReponseGlycemiqueServiceMock.cas(.enAttente))
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
}

#Preview("Repas — sans injection") {
    GraphiqueGlycemique.pourRepas(etat: ReponseGlycemiqueServiceMock.cas(.sansInjection))
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
}

#Preview("Sport — stable") {
    let service = ActivitesSportServiceMock.shared
    let activite = service.activites.first { $0.type == .yoga } ?? service.activites[0]
    GraphiqueGlycemique.pourSport(
        etat: service.reponse(pour: activite).map { .disponible($0) } ?? .donneesManquantes,
        dureeMinutes: activite.dureeMinutes
    )
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
}

#Preview("Sport — avec hypo") {
    GraphiqueGlycemique.pourSport(
        etat: .disponible(reponseSportHypoMock(dureeMinutes: 60)),
        dureeMinutes: 60
    )
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
}

/// Réponse synthétique : 130 mg/dL au départ, descente continue à
/// 62 mg/dL en fin d'effort. Extrait du `#Preview` parce que les
/// closures `@ViewBuilder` du macro n'autorisent pas la logique
/// impérative (boucle `while` + `append`).
private func reponseSportHypoMock(dureeMinutes: Int) -> ReponseGlycemiqueSport {
    let dureeSec = TimeInterval(dureeMinutes * 60)
    let pas: TimeInterval = 5 * 60
    let debut: TimeInterval = -30 * 60
    let fin: TimeInterval = dureeSec + 30 * 60

    var points: [PointCgmSport] = []
    var t = debut
    while t <= fin {
        let valeur: Double
        if t <= 0 {
            valeur = 130
        } else if t <= dureeSec {
            valeur = 130 - 68 * (t / dureeSec)
        } else {
            valeur = 62 + 5 * ((t - dureeSec) / (30 * 60))
        }
        points.append(PointCgmSport(secondesDepuisDebut: t, valeur: valeur))
        t += pas
    }
    return ReponseGlycemiqueSport(
        pointsCgm: points,
        glycemieDebut: 130,
        glycemieFin: 62,
        deltaMgDl: -68
    )
}
