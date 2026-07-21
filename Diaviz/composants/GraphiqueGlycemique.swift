//
//  GraphiqueGlycemique.swift
//  diaviz
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

    /// Hauteur du graphique. Par défaut agrandie pour les pages détail
    /// (le graph y est la vedette, pleine largeur sans carte).
    var hauteur: CGFloat = 280

    var body: some View {
        Group {
            switch etat {
            case .disponible(let config):
                CourbeGlycemiqueDetaillee(config: config)
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
        .frame(height: hauteur)
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
// telle quelle à la sous-vue `CourbeGlycemiqueDetaillee`.
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

        let (domaineY, yMarques) = Self.echelleY(
            pointsCourbe: pointsCourbe,
            marqueurs: marqueurs
        )

        return Self(
            header: "Réponse glycémique",
            pointsCourbe: pointsCourbe,
            couleurCourbe: reponse.verdict.couleur,
            domaineX: debut...fin,
            xMarques: Self.marquesTempsRepas(debut: debut, fin: fin),
            formatLabelTemps: Self.libelleTempsRepas,
            domaineY: domaineY,
            yMarques: yMarques,
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
    ///
    /// `nonisolated` parce que la fonction est purement calculatoire et
    /// référencée comme valeur dans `formatLabelTemps` (un closure
    /// non-isolé) : sans `nonisolated`, l'isolation `@MainActor` héritée
    /// de la `View` parente bloquerait l'assignation en Swift 6.
    nonisolated private static func libelleTempsRepas(_ secondes: TimeInterval) -> String {
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

        // Marqueur Début — cercle ouvert gris, label sur **une ligne**
        // (juste la valeur, comme le marqueur T0 côté repas). Le mot
        // « Début » est redondant : la métrique est déjà nommée juste en
        // dessous dans les cartes ; un libellé sur deux lignes prenait
        // trop de hauteur et chevauchait le label « T0 » de l'axe X
        // quand le point était bas dans le domaine.
        marqueurs.append(
            .init(
                temps: 0,
                valeur: reponse.glycemieDebut,
                couleur: .secondary,
                style: .cercleOuvert,
                label: .init(
                    texte: "\(Int(reponse.glycemieDebut))",
                    position: .haut,
                    alignement: .leading
                )
            )
        )

        // Marqueur Fin — cercle plein, couleur verdict, label une ligne
        // (même raison que Début).
        marqueurs.append(
            .init(
                temps: dureeSec,
                valeur: reponse.glycemieFin,
                couleur: couleurVerdict,
                style: .cerclePlein(taille: 80),
                label: .init(
                    texte: "\(Int(reponse.glycemieFin))",
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

        let (domaineY, yMarques) = Self.echelleY(
            pointsCourbe: pointsCourbe,
            marqueurs: marqueurs
        )

        return Self(
            header: "Glycémie pendant l'activité",
            pointsCourbe: pointsCourbe,
            couleurCourbe: couleurVerdict,
            domaineX: debut...fin,
            xMarques: Self.marquesTempsSport(debut: debut, dureeSec: dureeSec, fin: fin),
            formatLabelTemps: Self.libelleTempsSport,
            domaineY: domaineY,
            yMarques: yMarques,
            zoneActivite: 0...dureeSec,
            marqueurs: marqueurs
        )
    }

    /// Échelle Y qui **colle aux données** : le domaine englobe exactement
    /// les mesures réelles et les marqueurs (dont la valeur porte le point),
    /// avec une marge de respiration de 15 mg/dL arrondie à la dizaine.
    ///
    /// Data-driven plutôt que fixe [50, 220] : sinon un plancher à 50 laisse
    /// une large bande vide sous une courbe qui reste au-dessus de 110 (la
    /// « marge » visible sous le graphique). En hypo la borne basse descend
    /// naturellement pour capturer le creux ; en rebond muscu la borne haute
    /// monte au-delà de 180. Repères cliniques 70/100/140/180 affichés
    /// uniquement s'ils tombent dans le domaine, plus des paliers de 40
    /// au-delà de 180.
    static func echelleY(
        pointsCourbe: [GraphiqueGlycemique.PointCourbe],
        marqueurs: [GraphiqueGlycemique.Marqueur]
    ) -> (domaine: ClosedRange<Double>, marques: [Double]) {
        let valeurs = pointsCourbe.map(\.valeur) + marqueurs.map(\.valeur)
        let minData = valeurs.min() ?? 70
        let maxData = valeurs.max() ?? 180

        var bas = floor((minData - 15) / 10) * 10
        var haut = max(bas + 40, ceil((maxData + 15) / 10) * 10)

        // Marge minimale autour des lignes de seuil 70/180 : si les données
        // amènent une borne à moins de 20 mg/dL d'un seuil, on écarte encore
        // la borne. Sans ça, la ligne pointillée d'hypo/hyper se retrouve
        // collée au bord du cadre — visuellement un bloc épais (bord +
        // teinte de zone + ligne, tous au même endroit) au lieu d'un simple
        // repère au milieu du tracé.
        if (70 - bas) < 20 { bas -= 20 }
        if (haut - 180) < 20 && haut > 180 { haut += 20 }

        var marques: [Double] = [70, 100, 140, 180].filter { $0 >= bas && $0 <= haut }
        var palier = 220.0
        while palier <= haut {
            marques.append(palier)
            palier += 40
        }
        return (bas...haut, marques)
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
    nonisolated private static func libelleTempsSport(_ secondes: TimeInterval) -> String {
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
    let echantillons = ActivitesSportService.echantillonsApercu()
    let activite = echantillons.first { $0.type == .yoga } ?? echantillons[0]
    GraphiqueGlycemique.pourSport(
        etat: .disponible(ActivitesSportService.genererReponse(pour: activite)),
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
