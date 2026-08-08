//
//  SheetDetailSoiree.swift
//  diaviz
//

import Charts
import SwiftUI

/// Sheet **« Détail d'une soirée »** — raconte la chaîne complète d'un soir
/// analysé (fusion B2/B3) : courbe de glycémie parcourable au doigt (avec
/// l'insuline active en aire de fond), liste des événements de la nuit
/// (repas → correction → lente → hypo → réveil), constat B1, chips de
/// contexte.
///
/// La courbe et la liste sont **couplées** : faire glisser le curseur met en
/// évidence l'événement le plus proche, taper une ligne déplace le curseur.
/// Même expérience que le détail d'activité sportive (`FriseSeanceSportive`)
/// — les deux écrans racontent la même chose, une courbe glycémique et les
/// événements qui l'expliquent.
///
/// Réutilisable : présentée depuis la page « Hypos au coucher » (tap sur un
/// soir) et, à terme, depuis la sheet « Comparer à ce soir ».
///
/// Les faits bruts (rapides, repas) de la nuit sont rechargés au boot via
/// `ChargeurFaitsCoucher` ; le reste vient du soir fusionné et de la
/// `NightChartData` B1 déjà calculée. Purement factuel.
///
/// ## Défilement — deux pièges rencontrés ici (2026-08-07)
///
/// Cette sheet a saccadé au scroll pendant son développement. Le Liquid Glass
/// a d'abord été soupçonné **à tort** : le retirer n'a rien changé. Les deux
/// vraies causes, toutes deux dans le `body`, valent d'être retenues — elles
/// se reproduiraient à l'identique sur n'importe quel écran.
///
/// 1. **Écrire un `@State` depuis un `GeometryReader`.** `zoneTrace` était
///    réaffecté à chaque passe de layout pour aligner la piste d'insuline.
///    Or écrire un état pendant le layout en relance un : pendant le scroll,
///    la boucle tournait en continu. Corrigé par `majZoneTrace`, qui ignore
///    les variations sub-pixel.
///
/// 2. **Recalculer des agrégats dans le `body`.** `domaineY`, la couleur de
///    la courbe et les arrêts du dégradé d'insuline reparcouraient les ~120
///    points de la nuit à chaque frame. Ils sont désormais calculés une seule
///    fois au chargement, dans `RenduNuit`.
///
/// Le verre amplifiait le symptôme (plus coûteux à recomposer qu'un aplat)
/// mais ne le causait pas. Chercher d'abord les recompositions inutiles, pas
/// le matériau.
///
/// La sheet est depuis passée en **surfaces opaques** — décision de lisibilité,
/// pas de performance : au-dessus d'un graphique, le verre laissait
/// transparaître courbe et points derrière les lignes de la timeline.
struct SheetDetailSoiree: View {

    let soir: SoirCoucher
    /// Nuit B1 correspondante — porte la courbe, les zones et le constat.
    let nuitB1: NightChartData?
    /// Début du palier de dose courant (affiché sur la ligne lente).
    var changementDoseRecent: Date? = nil
    /// Ouvre le détail d'un repas (sheet dédiée, à venir). Le chevron de la
    /// ligne repas n'apparaît que si ce handler est fourni.
    var onOuvrirRepas: ((Date) -> Void)? = nil
    /// Faits injectés directement — pour les previews (court-circuite le hub).
    var faitsApercu: (rapides: [(heure: Date, dose: Double, correction: Bool)],
                      repas: [(heure: Date, glucides: Int)])? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var detail: DetailSoiree?

    /// Instant survolé sur la courbe de glycémie. `nil` quand le doigt n'est
    /// pas posé — la barre de contexte affiche alors le bilan de la nuit.
    @State private var heureCurseur: Date?
    /// Événement mis en évidence (aimantation du curseur, ou tap timeline).
    @State private var evenementActif: UUID?

    /// Distance d'aimantation du curseur sur un événement.
    private static let seuilAimantation: TimeInterval = 6 * 60

    /// Zone de tracé du graphe, mesurée à l'affichage. Sert à aligner la
    /// piste d'insuline (posée sous l'axe X, hors du `Chart`) exactement sur
    /// la même plage horizontale que la courbe.
    @State private var zoneTrace: CGRect = .zero

    /// Valeurs dérivées de `detail`, calculées **une seule fois** au
    /// chargement. Elles parcourent toute la courbe de la nuit (~120 points) :
    /// les recalculer dans le `body` les refaisait à chaque frame de
    /// défilement, ce qui saccadait le scroll de la sheet.
    @State private var rendu: RenduNuit?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let detail {
                    contenu(detail)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(titreNuit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task { charger() }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Chargement

    private func charger() {
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -1, to: soir.date) ?? soir.date
        let faits = faitsApercu ?? (
            rapides: ChargeurFaitsCoucher.rapides(modelContext, depuis: borne),
            repas: ChargeurFaitsCoucher.repas(modelContext, depuis: borne)
        )
        let profil = ProfilService.shared.profil
        detail = CalculDetailSoiree.analyser(
            soir: soir,
            nuitB1: nuitB1,
            rapides: faits.rapides,
            repas: faits.repas,
            changementDoseRecent: changementDoseRecent,
            config: ConfigEndormissement(
                seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
                diaHeures: profil.dureeActionInsulineHeures,
                picMinutes: profil.insulineRapide.picActionMinutes
            )
        )
        if let detail {
            rendu = RenduNuit(detail: detail, seuilHyper: seuilHyper, plafondIOB: Self.plafondIOB)
        }
    }

    private var titreNuit: String {
        "Nuit du \(soir.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))"
    }

    // MARK: - Contenu

    @ViewBuilder
    private func contenu(_ detail: DetailSoiree) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hero : la courbe de glycémie de la nuit en vedette, pleine
            // largeur sans carte, tout en haut (même langage visuel que les
            // détails repas/sport). L'insuline active y est tracée en aire de
            // fond plutôt que dans un second graphe : les deux se lisent
            // ensemble (« la glycémie descend pendant que l'IOB est encore
            // haut »), les séparer obligeait à aligner les instants de tête.
            if !detail.courbe.isEmpty {
                sectionGlycemie(detail)
            }

            if detail.evenements.isEmpty {
                Text("Pas assez de données CGM pour reconstruire cette nuit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            } else {
                timeline(detail)
            }

            sectionConstatB1(detail.constatB1)
            sectionContexte
        }
        .padding(.top, 8)
    }

    // MARK: - Timeline

    private func timeline(_ detail: DetailSoiree) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(detail.evenements.enumerated()), id: \.element.id) { index, evenement in
                LigneTimelineSoiree(
                    evenement: evenement,
                    estDernier: index == detail.evenements.count - 1,
                    actif: evenement.id == evenementActif,
                    onOuvrirRepas: onOuvrirRepas,
                    onSelectionner: { basculerSelection(evenement) }
                )
                if index < detail.evenements.count - 1 {
                    Divider().padding(.leading, 46)
                }
            }
        }
        .carteListeEvenements()
    }

    /// Met à jour la zone de tracé mémorisée, en ignorant les variations
    /// sub-pixel. Sans ce filtre, chaque passe de layout réécrivait le
    /// `@State` et relançait une recomposition.
    private func majZoneTrace(_ nouvelle: CGRect) {
        guard abs(nouvelle.minX - zoneTrace.minX) > 0.5
            || abs(nouvelle.width - zoneTrace.width) > 0.5 else { return }
        zoneTrace = nouvelle
    }

    /// Tap sur une ligne de timeline → pose le curseur sur cet événement (ou
    /// le retire s'il était déjà actif).
    ///
    /// Pas de `withAnimation` : il propagerait la transition au `Chart`, qui
    /// ré-interpolerait alors son tracé — la courbe repasserait visiblement
    /// par une version anguleuse avant de retrouver son lissage `catmullRom`.
    /// Les éléments à animer portent leur propre `.animation(_:value:)`.
    private func basculerSelection(_ evenement: EvenementSoiree) {
        if evenementActif == evenement.id {
            evenementActif = nil
            heureCurseur = nil
        } else {
            evenementActif = evenement.id
            heureCurseur = evenement.heure
        }
    }

    // MARK: - Courbe glycémie

    private func sectionGlycemie(_ detail: DetailSoiree) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glycémie · 21h → 07h")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            // Barre de contexte **au-dessus** de la courbe : pendant un
            // scrub, le doigt masque tout ce qui est en dessous du point
            // touché (même raison que sur le détail d'activité sportive).
            barreContexte(detail)

            Chart {
                // Bande de cible — même repère visuel que le détail
                // d'activité sportive : on voit d'un coup d'œil ce qui est
                // dedans et ce qui n'y est pas.
                RectangleMark(
                    xStart: .value("Début", detail.courbe.first?.time ?? Date()),
                    xEnd: .value("Fin", detail.courbe.last?.time ?? Date()),
                    yStart: .value("Cible bas", Double(detail.seuilHypo)),
                    yEnd: .value("Cible haut", seuilHyper)
                )
                .foregroundStyle(.green.opacity(0.08))


                // Seuil hypo.
                RuleMark(y: .value("Seuil", detail.seuilHypo))
                    .foregroundStyle(Color.red.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(detail.seuilHypo)")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }

                RuleMark(y: .value("Hyper", seuilHyper))
                    .foregroundStyle(Color.orange.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                ForEach(detail.courbe) { point in
                    LineMark(
                        x: .value("Heure", point.time),
                        y: .value("mg/dL", point.value)
                    )
                    .foregroundStyle(rendu?.couleurCourbe ?? .primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Marqueurs d'événements sur la courbe. Celui qui est
                // sélectionné grossit pour faire le lien avec la timeline.
                ForEach(detail.evenements) { evenement in
                    if let marqueur = marqueur(evenement, courbe: detail.courbe) {
                        PointMark(
                            x: .value("Heure", marqueur.heure),
                            y: .value("mg/dL", marqueur.valeur)
                        )
                        .foregroundStyle(marqueur.couleur)
                        .symbolSize(evenement.id == evenementActif ? marqueur.taille * 2.4 : marqueur.taille)
                    }
                }

                // Curseur de scrub. Le trait vertical traverse le graphe **et**
                // la bande d'insuline : les deux se lisent au même instant.
                if let heureCurseur {
                    RuleMark(x: .value("Curseur", heureCurseur))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                    if let valeur = valeurCourbe(a: heureCurseur, dans: detail.courbe) {
                        PointMark(
                            x: .value("Curseur", heureCurseur),
                            y: .value("mg/dL", valeur)
                        )
                        .symbol {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                        }
                    }
                }
            }
            .chartYScale(domain: rendu?.domaineY ?? 50...250)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().locale(Locale(identifier: "fr_FR")))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { valeur in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let v = valeur.as(Double.self) {
                            Text("\(Int(v))").font(.caption2).monospacedDigit()
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.top, 12).padding(.bottom, 6)
            }
            .frame(height: 260)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotFrame = proxy.plotFrame {
                        let rect = geo[plotFrame]
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(gestureScrub(proxy: proxy, rect: rect, detail: detail))
                            // Mémorise la zone de tracé pour aligner la piste
                            // d'insuline posée sous l'axe.
                            //
                            // Écrit **seulement** si la géométrie a vraiment
                            // bougé : `rect` est recalculé à chaque passe de
                            // layout, et réécrire un `@State` identique à
                            // chaque frame relançait une recomposition en
                            // boucle — c'est ce qui saccadait le défilement
                            // de la sheet.
                            .onAppear { majZoneTrace(rect) }
                            .onChange(of: rect) { _, nouvelle in majZoneTrace(nouvelle) }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: evenementActif)
            .accessibilityLabel(accessibiliteCourbe(detail))

            // Collée sous l'axe X plutôt qu'espacée comme les autres blocs :
            // la piste appartient visuellement au graphe (même plage
            // horizontale, même curseur) — détachée, elle paraissait orpheline.
            pisteIOB(detail)
                .padding(.top, -6)

            noteIOBHypo(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Note factuelle sous la courbe : insuline rapide encore active au
    /// moment de la première hypo. Conservée depuis l'ancien graphe d'IOB
    /// séparé — c'est souvent l'explication de l'hypo, elle mérite d'être
    /// écrite en toutes lettres et pas seulement lisible sur une aire.
    @ViewBuilder
    private func noteIOBHypo(_ detail: DetailSoiree) -> some View {
        if let iobHypo = detail.iobAuMomentHypo,
           let premiereHypo = detail.evenements.first(where: {
               if case .hypo = $0.genre { return true }; return false
           }) {
            Text("~\(String(format: "%.1f", iobHypo))u encore actif au moment de l'hypo (\(heureFr(premiereHypo.heure))).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Glisser (ou toucher) pose le curseur ; relâcher le retire, ce qui
    /// ramène la barre au bilan de la nuit. Le curseur s'aimante sur les
    /// événements proches, pour que les valeurs lues correspondent
    /// exactement à celles de la timeline.
    private func gestureScrub(proxy: ChartProxy, rect: CGRect, detail: DetailSoiree) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { valeur in
                let x = valeur.location.x - rect.minX
                guard let brut: Date = proxy.value(atX: x) else { return }
                let borne = borner(brut, dans: detail.courbe)
                if let proche = evenementLePlusProche(de: borne, dans: detail.evenements),
                   abs(proche.heure.timeIntervalSince(borne)) <= Self.seuilAimantation {
                    heureCurseur = proche.heure
                    if evenementActif != proche.id { evenementActif = proche.id }
                } else {
                    heureCurseur = borne
                    if evenementActif != nil { evenementActif = nil }
                }
            }
            .onEnded { _ in
                heureCurseur = nil
                evenementActif = nil
            }
    }

    // MARK: - Barre de contexte
    //
    // Une seule ligne, hauteur fixe (aucun saut de mise en page entre les
    // deux états). Curseur posé → l'instant survolé. Sinon → bornes de la
    // nuit, pour que la lecture reste informative sans interaction.

    private func barreContexte(_ detail: DetailSoiree) -> some View {
        HStack(spacing: 8) {
            if let heureCurseur {
                contenuInstant(heureCurseur, detail: detail)
            } else {
                contenuBilan(detail)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fond neutre **systématique**, teinte de l'événement par-dessus : la
        // barre doit rester une capsule lisible même sans sélection (avec la
        // seule teinte, elle disparaissait, `teinteBarre` valant `.clear`).
        .surfaceCarte(.compact, fond: Color(.secondarySystemGroupedBackground))
        .surfaceCarte(.compact, fond: teinteBarre(detail))
    }

    /// Teinte de la barre — prend la couleur de l'événement sélectionné,
    /// transparente sinon (le fond neutre reste visible dessous). Même
    /// comportement que la barre de contexte du détail d'activité sportive.
    private func teinteBarre(_ detail: DetailSoiree) -> Color {
        guard let evenement = detail.evenements.first(where: { $0.id == evenementActif })
        else { return .clear }
        return evenement.couleur.opacity(0.16)
    }

    @ViewBuilder
    private func contenuInstant(_ heure: Date, detail: DetailSoiree) -> some View {
        let evenement = detail.evenements.first { $0.id == evenementActif }
        let valeur = valeurCourbe(a: heure, dans: detail.courbe)

        if let evenement {
            Image(systemName: evenement.icone)
                .font(.footnote)
                .foregroundStyle(evenement.couleur)
        }

        Text(Self.formatterHeure.string(from: heure))
            .font(.subheadline.weight(.medium))
            .monospacedDigit()

        if let evenement {
            Text(libelleCourt(evenement))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        Spacer(minLength: 4)

        // IOB à cet instant — donne la valeur chiffrée de la piste bleue, qui
        // ne porte aucune graduation. Libellée : sans le mot « IOB », le seul
        // rappel de couleur ne suffit pas à comprendre ce que dit ce chiffre.
        if let iob = iobA(heure, dans: detail), iob > 0.05 {
            HStack(spacing: 3) {
                Text("IOB")
                    .font(.caption2.weight(.semibold))
                Text(iob.doseInsulineFormatee)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.blue)
        }

        if let valeur {
            Text("\(Int(valeur.rounded()))")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valeur < Double(detail.seuilHypo) ? .red : .primary)
        }
    }

    @ViewBuilder
    private func contenuBilan(_ detail: DetailSoiree) -> some View {
        let valeurs = detail.courbe.map(\.value)
        Text("Nuit")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Spacer(minLength: 4)
        if let bas = valeurs.min(), let haut = valeurs.max() {
            Text("min \(Int(bas))")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(bas < Double(detail.seuilHypo) ? .red : .primary)
            Text("·")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("max \(Int(haut))")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
    }

    /// Libellé compact d'un événement pour la barre de contexte — la
    /// timeline en dessous porte déjà le détail complet.
    private func libelleCourt(_ evenement: EvenementSoiree) -> String {
        switch evenement.genre {
        case .repas(_, let resucrage):  return resucrage ? "Resucrage" : "Repas"
        case .correction(let dose, _):  return "Correction · \(dose.doseInsulineFormatee)"
        case .lente(let dose, _):       return "Lente · \(dose.doseInsulineFormatee)"
        case .hypo:                     return "Hypoglycémie"
        case .reveil:                   return "Réveil"
        }
    }

    // MARK: - Helpers de scrub

    private func borner(_ date: Date, dans courbe: [GlucosePoint]) -> Date {
        guard let premier = courbe.first?.time, let dernier = courbe.last?.time else { return date }
        return min(max(date, premier), dernier)
    }

    private func evenementLePlusProche(de heure: Date, dans evenements: [EvenementSoiree]) -> EvenementSoiree? {
        evenements.min {
            abs($0.heure.timeIntervalSince(heure)) < abs($1.heure.timeIntervalSince(heure))
        }
    }

    /// Valeur de la courbe au point le plus proche — la courbe est déjà
    /// rééchantillonnée à pas régulier par B1, pas besoin d'interpoler.
    private func valeurCourbe(a heure: Date, dans courbe: [GlucosePoint]) -> Double? {
        courbe.min { abs($0.time.timeIntervalSince(heure)) < abs($1.time.timeIntervalSince(heure)) }?.value
    }

    private static let formatterHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "H'h'mm"
        return f
    }()

    private struct Marqueur {
        let heure: Date
        let valeur: Double
        let couleur: Color
        let taille: CGFloat
    }

    // MARK: - Piste d'insuline active
    //
    // Pilule posée **sous l'axe X**, hors du graphe : la courbe garde toute
    // sa hauteur, la piste se lit comme une frise temporelle secondaire.
    // Elle reste alignée au pixel près sur la zone de tracé grâce à
    // `zoneTrace`, mesurée sur le graphe lui-même.
    //
    // C'est un **dégradé continu**, pas une suite de rectangles : l'insuline
    // active décroît de façon lisse, une bande en escalier donnait un rendu
    // haché qui suggérait des paliers inexistants.
    //
    // Le motif est prévu pour accueillir d'autres pistes (glucides actifs,
    // activité physique…) : il suffira d'empiler d'autres pilules dessous.

    @ViewBuilder
    private func pisteIOB(_ detail: DetailSoiree) -> some View {
        let stops = rendu?.stopsIOB ?? []
        if !stops.isEmpty, zoneTrace.width > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Insuline active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Piste neutre en fond, dégradé par-dessus : les zones sans
                // insuline (quasi transparentes dans le dégradé) laissent voir
                // la piste au lieu du fond de la page.
                Capsule()
                    .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    .frame(width: zoneTrace.width, height: 16)
                    .overlay(alignment: .leading) { curseurPiste(detail) }
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .padding(.leading, zoneTrace.minX)
            .accessibilityLabel("Insuline active au fil de la nuit")
        }
    }

    /// Repère du curseur sur la piste — même instant que sur la courbe.
    @ViewBuilder
    private func curseurPiste(_ detail: DetailSoiree) -> some View {
        if let heureCurseur, let fraction = fractionTemporelle(heureCurseur, dans: detail) {
            Capsule()
                .fill(Color.primary.opacity(0.7))
                .frame(width: 2, height: 18)
                .offset(x: fraction * zoneTrace.width - 1)
        }
    }

    /// Position relative d'un instant dans la fenêtre de la nuit, `nil` si la
    /// courbe est trop courte pour définir une fenêtre.
    private func fractionTemporelle(_ instant: Date, dans detail: DetailSoiree) -> Double? {
        guard let debut = detail.courbe.first?.time,
              let fin = detail.courbe.last?.time,
              fin > debut else { return nil }
        let brut = instant.timeIntervalSince(debut) / fin.timeIntervalSince(debut)
        return min(max(brut, 0), 1)
    }

    /// Seuil d'hyperglycémie du profil — la bande de cible et la ligne haute
    /// suivent le réglage utilisateur, comme partout ailleurs dans l'app.
    private var seuilHyper: Double {
        ProfilService.shared.profil.seuilsGlycemiques.hyperglycemie
    }

    /// Plafond de l'échelle d'insuline active, en unités. **Fixe et absolu**
    /// — c'est ce qui rend les nuits comparables entre elles : une nuit à
    /// 1u et une nuit à 5u ne doivent pas se ressembler.
    ///
    /// Une normalisation sur le maximum de la nuit (première version) donnait
    /// exactement le même rendu dans les deux cas et détruisait donc
    /// l'information de dose. Au-delà du plafond, l'intensité sature — la
    /// valeur exacte reste lisible au scrub.
    private static let plafondIOB: Double = 6


    /// IOB rapide au plus proche d'un instant — affichée pendant le scrub.
    private func iobA(_ heure: Date, dans detail: DetailSoiree) -> Double? {
        detail.courbeIOB
            .min { abs($0.date.timeIntervalSince(heure)) < abs($1.date.timeIntervalSince(heure)) }?
            .iob
    }

    /// Position + style du marqueur d'un événement sur la courbe. Repas et
    /// réveil ne sont pas marqués (timeline suffit) pour garder la courbe lisible.
    private func marqueur(_ evenement: EvenementSoiree, courbe: [GlucosePoint]) -> Marqueur? {
        func valeurA(_ t: Date) -> Double? {
            courbe.min(by: { abs($0.time.timeIntervalSince(t)) < abs($1.time.timeIntervalSince(t)) })?.value
        }
        switch evenement.genre {
        case .correction:
            guard let v = valeurA(evenement.heure) else { return nil }
            return Marqueur(heure: evenement.heure, valeur: v, couleur: .indigo, taille: 42)
        case .lente:
            guard let v = valeurA(evenement.heure) else { return nil }
            return Marqueur(heure: evenement.heure, valeur: v, couleur: .secondary, taille: 42)
        case .hypo(let valeur, _):
            return Marqueur(heure: evenement.heure, valeur: Double(valeur), couleur: .red, taille: 55)
        case .repas, .reveil:
            return nil
        }
    }

    private func accessibiliteCourbe(_ detail: DetailSoiree) -> String {
        let hypos = detail.evenements.compactMap { e -> String? in
            if case let .hypo(valeur, _) = e.genre { return "\(valeur) mg/dL à \(heureFr(e.heure))" }
            return nil
        }
        return hypos.isEmpty
            ? "Courbe de glycémie de la nuit, aucune hypoglycémie."
            : "Courbe de glycémie de la nuit. Hypoglycémies : \(hypos.joined(separator: ", "))."
    }

    // MARK: - Constat B1

    @ViewBuilder
    private func sectionConstatB1(_ constat: ConstatB1Nuit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tendance basale cette nuit (B1)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                switch constat {
                case let .analysee(derive, categorie):
                    Image(systemName: symboleCategorie(categorie))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(couleurCategorie(categorie))
                    Text("Nuit profonde : dérive \(String(format: "%+d", derive)) mg/dL (\(libelleCategorie(categorie)))")
                        .font(.footnote)
                case let .exclue(motif):
                    Image(systemName: "circle.dashed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Nuit exclue de l'analyse basale — \(motif.lowercased())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .indisponible:
                    Image(systemName: "questionmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Pas de données d'analyse basale pour cette nuit")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
    }

    private func symboleCategorie(_ categorie: CategorieNuit) -> String {
        switch categorie {
        case .stable:         return "arrow.right"
        case .tendanceBasse:  return "arrow.down.right"
        case .tendanceHaute:  return "arrow.up.right"
        }
    }

    private func couleurCategorie(_ categorie: CategorieNuit) -> Color {
        switch categorie {
        case .stable:         return .green
        case .tendanceBasse:  return .red
        case .tendanceHaute:  return .orange
        }
    }

    private func libelleCategorie(_ categorie: CategorieNuit) -> String {
        switch categorie {
        case .stable:         return "stable"
        case .tendanceBasse:  return "descendante"
        case .tendanceHaute:  return "ascendante"
        }
    }

    // MARK: - Contexte (chips agrandies)

    private var sectionContexte: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contexte")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            FlowLayout(spacing: 8) {
                if soir.chargeVisible {
                    ChipCharge(charge: soir.charge, taille: .large)
                }
                ForEach(soir.chipsContexte) { chip in
                    ChipContexte(chip: chip, taille: .large)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte()
    }

    private func heureFr(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02dh%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Valeurs dérivées de la nuit

/// Tout ce qui se déduit de la nuit par un parcours complet de ses points —
/// calculé **une fois** au chargement plutôt qu'à chaque rendu.
///
/// Ces valeurs étaient d'abord des fonctions appelées depuis le `body` : sur
/// une nuit de 10 h (~120 points), elles reparcouraient toute la courbe à
/// chaque frame de défilement et faisaient saccader la sheet.
private struct RenduNuit {
    let domaineY: ClosedRange<Double>
    /// Couleur de la courbe : rouge si hypo, orange si sortie par le haut,
    /// vert si tout est resté en cible.
    let couleurCourbe: Color
    let minGlycemie: Double
    let maxGlycemie: Double
    /// Arrêts du dégradé de la piste d'insuline active, positionnés sur la
    /// fenêtre de la courbe glycémique.
    let stopsIOB: [Gradient.Stop]
    let debut: Date?
    let fin: Date?

    init(detail: DetailSoiree, seuilHyper: Double, plafondIOB: Double) {
        let valeurs = detail.courbe.map(\.value)
        let bas = valeurs.min() ?? 70
        let haut = valeurs.max() ?? 180
        minGlycemie = bas
        maxGlycemie = haut

        let planche = max(50, min(bas, Double(detail.seuilHypo)) - 20)
        domaineY = planche...(haut + 20)

        if bas < Double(detail.seuilHypo) {
            couleurCourbe = .red
        } else if haut > seuilHyper {
            couleurCourbe = .orange
        } else {
            couleurCourbe = .green
        }

        debut = detail.courbe.first?.time
        fin = detail.courbe.last?.time

        if let debut, let fin, fin > debut,
           detail.courbeIOB.contains(where: { $0.iob > 0.05 }) {
            let duree = fin.timeIntervalSince(debut)
            let stops = detail.courbeIOB.map { point -> Gradient.Stop in
                let fraction = min(max(point.date.timeIntervalSince(debut) / duree, 0), 1)
                let opacite = point.iob > 0.05
                    ? 0.15 + min(point.iob / plafondIOB, 1) * 0.7
                    : 0.04
                return Gradient.Stop(color: .blue.opacity(opacite), location: fraction)
            }
            stopsIOB = stops.count >= 2 ? stops : []
        } else {
            stopsIOB = []
        }
    }
}

// MARK: - Présentation d'un événement de nuit

/// Icône, couleur et titre d'un événement — partagés par la liste **et** par
/// la barre de contexte du graphe, pour que sélectionner une ligne teinte la
/// barre de la même couleur (comportement du détail d'activité sportive).
extension EvenementSoiree {

    var icone: String {
        switch genre {
        case .repas(_, let resucrage): return resucrage ? "cross.case.fill" : "fork.knife"
        case .correction:  return "syringe"
        case .lente:       return "syringe.fill"
        case .hypo:        return "exclamationmark.triangle.fill"
        case .reveil:      return "sunrise.fill"
        }
    }

    var couleur: Color {
        switch genre {
        case .repas(_, let resucrage): return resucrage ? .red : .green
        case .correction:  return .blue
        case .lente:       return .indigo
        case .hypo:        return .red
        case .reveil:      return .orange
        }
    }

    var titre: String {
        switch genre {
        case .repas(_, let resucrage): return resucrage ? "Resucrage" : "Repas"
        case .correction:  return "Correction rapide"
        case .lente:       return "Lente"
        case .hypo:        return "Hypo"
        case .reveil:      return "Réveil"
        }
    }
}

// MARK: - Ligne de timeline

/// Une ligne de la liste d'événements de la nuit — icône teintée, titre,
/// sous-titre factuel, valeur à droite.
///
/// Même langage visuel que la liste de `FriseSeanceSportive` (détail
/// d'activité sportive) : les deux écrans racontent la même chose — une
/// courbe glycémique et les événements qui l'expliquent — ils doivent se
/// lire de la même façon. L'ancienne présentation en timeline verticale
/// (pastilles reliées par un trait) a été abandonnée pour cette raison.
private struct LigneTimelineSoiree: View {

    let evenement: EvenementSoiree
    let estDernier: Bool
    /// Événement pointé par le curseur de la courbe — surbrillance de liaison.
    var actif: Bool = false
    var onOuvrirRepas: ((Date) -> Void)? = nil
    /// Pose le curseur de la courbe sur cet événement. Non appelé pour un
    /// repas, dont le tap garde son action existante (ouvrir le détail).
    var onSelectionner: (() -> Void)? = nil

    var body: some View {
        LigneEvenementCourbe(
            icone: symbole,
            couleur: teinte,
            titre: titre,
            sousTitre: sousTitre,
            detail: detail,
            actif: actif,
            enAlerte: estAlerte,
            afficheChevron: estRepas && onOuvrirRepas != nil
        )
        // Le repas garde son action existante (ouvrir son détail) : elle est
        // plus riche qu'un simple positionnement de curseur. Les autres
        // genres, qui n'ont pas d'action propre, servent la sélection.
        .onTapGesture {
            if estRepas {
                onOuvrirRepas?(evenement.heure)
            } else {
                onSelectionner?()
            }
        }
    }

    // MARK: Dérivés par genre

    private var estRepas: Bool {
        if case .repas = evenement.genre { return true }
        return false
    }

    private var estAlerte: Bool {
        if case .hypo = evenement.genre { return true }
        return false
    }

    private var symbole: String { evenement.icone }
    private var teinte: Color { evenement.couleur }
    private var titre: String { evenement.titre }

    /// Valeur mise à droite — la donnée chiffrée principale de l'événement.
    private var detail: String {
        switch evenement.genre {
        case let .repas(glucides, _):   return "\(glucides)g"
        case let .correction(dose, _):  return dose.doseInsulineFormatee
        case let .lente(dose, _):       return dose.doseInsulineFormatee
        case let .hypo(valeur, _):      return "\(valeur)"
        case let .reveil(valeur):       return "\(valeur)"
        }
    }

    /// Contexte à gauche : heure, puis la précision propre au genre.
    private var sousTitre: String {
        let heure = heureFr(evenement.heure)
        switch evenement.genre {
        case .repas:
            return heure
        case let .correction(_, glycemie):
            return glycemie.map { "\(heure) · glycémie \($0) mg/dL" } ?? heure
        case let .lente(_, depuis):
            let d = depuis.map {
                " · depuis le \($0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))"
            } ?? ""
            return heure + d
        case let .hypo(_, delai):
            let d = delai.map { " · t+\(formatDelai($0)) après la lente" } ?? ""
            return "\(heure)\(d) · mg/dL"
        case .reveil:
            return "\(heure) · mg/dL"
        }
    }

    private func formatDelai(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
    }

    private func heureFr(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02dh%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Détail soirée — pipeline réel") {
    // Exerce le vrai pipeline : nuit synthétique B1 + soir fusionné dérivé.
    let analyse = CalculAnalyseBasale.apercu()
    let nuit = analyse.nightChartData.first!
    let correction = (heure: nuit.basaleTime.addingTimeInterval(-20 * 60), dose: 4.0, correction: true)
    let soir = SoirCoucher(
        id: UUID(), date: nuit.date, glycemie: Int(nuit.startGlucose), tendance: .baisse,
        correction: 4, glucides: nil,
        sport: SportResume(type: "Course", intensite: "modéré", dureeMinutes: 45),
        iob: 1.2, charge: .intense, categorieB1: .tendanceBasse,
        enHypo: true, delaiHypoMinutes: nil, issueCorrection: .surCorrection
    )
    return SheetDetailSoiree(
        soir: soir,
        nuitB1: nuit,
        changementDoseRecent: Calendar.current.date(byAdding: .day, value: -12, to: Date()),
        onOuvrirRepas: { _ in },
        faitsApercu: (
            rapides: [correction, (heure: nuit.basaleTime.addingTimeInterval(-3 * 3600), dose: 6, correction: false)],
            repas: [(heure: nuit.basaleTime.addingTimeInterval(-3 * 3600), glucides: 65)]
        )
    )
}
#endif
