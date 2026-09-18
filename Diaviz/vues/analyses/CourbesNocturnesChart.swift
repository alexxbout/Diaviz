//
//  CourbesNocturnesChart.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI
import Charts

// MARK: - Tokens couleur partagés

/// Couleurs spécifiques au graphique d'analyse basale — alignées sur
/// le langage du design system « santé » (rouge hypo, ambre tendance,
/// violet lente, bleu rapide, vert resucrage).
///
/// Définies localement plutôt que dans un asset catalog parce que ces
/// teintes sont propres à ce graphique — les autres vues de l'app
/// utilisent les couleurs sémantiques système (`.red`, `.green`, …).
private extension Color {
    /// Ambre — utilisée pour le seuil 180 (RuleMark) et le badge
    /// « Partielle ». Représente la limite hyper.
    static let basaleTendance     = Color(red: 186/255, green: 117/255, blue:  23/255)
    /// Violet vif — couleur de la **courbe de tendance moyenne** (vue
    /// agrégée). Choisie distincte du violet plus clair de
    /// `basaleLenteRepere` pour éviter la confusion.
    static let basaleTendanceMoy  = Color(red: 110/255, green:  67/255, blue: 217/255)
    static let basaleLenteRepere  = Color(red: 127/255, green: 119/255, blue: 221/255)
    static let basaleHypo         = Color(red: 226/255, green:  75/255, blue:  74/255)
    /// Orange vif pour les segments de courbe au-dessus de 180.
    static let basaleHyper        = Color(red: 240/255, green: 140/255, blue:  30/255)
    static let basaleRapide       = Color(red:  55/255, green: 138/255, blue: 221/255)
    static let basaleResucrage    = Color(red: 151/255, green: 196/255, blue:  89/255)
    /// Pink/magenta pour le point repas — distinct du brun (mangé,
    /// pas terrible) et de toutes les autres teintes de la palette.
    static let basaleRepas        = Color(red: 230/255, green:  95/255, blue: 175/255)
    /// Couleur de la courbe unique en vue « Par nuit » — gris foncé
    /// neutre, les portions hypo/hyper portent leur propre teinte.
    static let basaleCourbeNuit   = Color(red:  95/255, green:  94/255, blue:  90/255)
    static let basaleCourbeNuitDark = Color(red: 136/255, green: 135/255, blue: 128/255)
}

// MARK: - Segmentation glycémique (coloration des portions hypo/hyper)

/// Catégorie de glycémie pour la coloration des segments de courbe.
private enum CategorieGlycemie {
    case hypo       // < 70 mg/dL → segment rouge
    case normal     // 70-180 → couleur par défaut
    case hyper      // > 180 → segment orange

    init(_ valeur: Double) {
        if valeur < 70 { self = .hypo }
        else if valeur > 180 { self = .hyper }
        else { self = .normal }
    }
}

/// Un segment contigu de courbe partageant la même catégorie. Inclut
/// volontairement le **point de bascule** dans les deux segments
/// adjacents pour qu'il n'y ait pas de trou visuel à la jonction.
private struct SegmentColore: Identifiable {
    let id = UUID()
    let categorie: CategorieGlycemie
    let points: [GlucosePoint]
}

/// Coupe une série de points en segments contigus par catégorie. À
/// chaque changement de catégorie, on duplique le point de transition
/// dans les deux segments → continuité visuelle.
private func segmenter(_ points: [GlucosePoint]) -> [SegmentColore] {
    guard let premier = points.first else { return [] }
    var segments: [SegmentColore] = []
    var cur: [GlucosePoint] = [premier]
    var catCur = CategorieGlycemie(premier.value)
    for p in points.dropFirst() {
        let catP = CategorieGlycemie(p.value)
        if catP != catCur {
            cur.append(p)
            segments.append(SegmentColore(categorie: catCur, points: cur))
            cur = [p]
            catCur = catP
        } else {
            cur.append(p)
        }
    }
    if !cur.isEmpty {
        segments.append(SegmentColore(categorie: catCur, points: cur))
    }
    return segments
}

/// Retourne la couleur d'un segment selon sa catégorie. Le segment
/// `.normal` retombe sur la couleur par défaut passée en paramètre
/// (gris foncé sur la vue « Par nuit », ambre sur la tendance « Toutes »).
private func couleurSegment(_ cat: CategorieGlycemie, defaut: Color) -> Color {
    switch cat {
    case .hypo:    return .basaleHypo
    case .normal:  return defaut
    case .hyper:   return .basaleHyper
    }
}

// MARK: - Mode d'affichage (segmented picker)

/// Sélection courante du picker en tête du graphique. Visible au-delà
/// du fichier parce que l'init preview de `CourbesNocturnesChart`
/// l'expose en paramètre — les previews du même module en ont besoin.
enum ModeAffichageGraphiqueBasale: String, CaseIterable, Identifiable, Sendable {
    case toutes = "Toutes"
    case parNuit = "Par nuit"
    public var id: String { rawValue }
}

private typealias ModeAffichage = ModeAffichageGraphiqueBasale

// MARK: - Lissage / sous-échantillonnage

/// Moyenne mobile (fenêtre `window`) suivie d'un sous-échantillonnage
/// (1 point sur `step`). Réduit le bruit visuel des séries à 5 min
/// et allège le rendu Chart (passe de 121 à ~30-40 points).
///
/// Effectué côté pré-processing plutôt que dans Swift Charts — la
/// librairie ne fournit pas de modificateur de lissage et un trop
/// grand nombre de points fait pâtir le type-checker.
private func lisser(_ points: [GlucosePoint], window: Int = 3, step: Int = 2) -> [GlucosePoint] {
    guard points.count > window else { return points }
    let radius = window / 2
    var out: [GlucosePoint] = []
    out.reserveCapacity(points.count / step + 1)
    var i = radius
    while i < points.count - radius {
        let slice = points[(i - radius)...(i + radius)]
        let moyenne = slice.map(\.value).reduce(0, +) / Double(slice.count)
        out.append(GlucosePoint(time: points[i].time, value: moyenne))
        i += step
    }
    return out
}

// MARK: - Calcul de plage Y avec padding

/// Renvoie une plage Y qui couvre toutes les valeurs `+/- padding`
/// (10 mg/dL par défaut), arrondie au multiple de 5 le plus large pour
/// laisser respirer les courbes près des bords.
///
/// Garde une fourchette « confortable » même quand les valeurs sont
/// dans la cible — borne à au moins `[60, 200]` pour que les RuleMarks
/// 70/180 restent visibles. Et à au plus `[20, 400]` pour anti-explosion.
private func plageYAvecPadding(_ valeurs: [Double], padding: Double = 10) -> ClosedRange<Double> {
    guard let mn = valeurs.min(), let mx = valeurs.max() else { return 40...250 }
    let mnPadded = floor((mn - padding) / 5) * 5
    let mxPadded = ceil((mx + padding) / 5) * 5
    // Force l'inclusion des seuils 70/180 et borne en dehors de
    // l'absurde (anti-spike valeur ML aberrante).
    let bas = min(60, max(20, mnPadded))
    let haut = max(200, min(400, mxPadded))
    return bas...haut
}

// MARK: - Composant racine

/// Carte 3 — graphique d'analyse basale, organisé en 2 vues
/// interchangeables via un picker `.segmented` :
///
///   - **Toutes** : superposition des courbes lissées + tendance moyenne,
///     marqueurs lente / hypos / rapide / resucrage.
///   - **Par nuit** : 3 blocs verticaux (graphique + barre zones
///     interactive + grille stats). Le tap sur une zone zoome le
///     graphique et adapte les stats.
struct CourbesNocturnesChart: View {

    let nights: [NightChartData]
    @Binding var mode: ModeAffichageGraphiqueBasale
    @Binding var indexSelectionne: Int
    /// Charge d'activité continue de la semaine précédant une nuit donnée —
    /// contexte transverse affiché dans la carte verdict de la vue « Par
    /// nuit ». Fourni par le parent, qui seul a accès au `ModelContext`.
    let chargePour: (Date) -> SyntheseChargeContinue
    /// Stades de sommeil HealthKit de la nuit **actuellement affichée** en
    /// vue « Par nuit » — `[]` si la donnée est indisponible (Watch pas
    /// portée, autorisation refusée) ou si le réglage overlay est désactivé.
    /// Uniquement consommé par `VueGraphiqueParNuit` : la vue « Toutes »
    /// superpose plusieurs nuits, un overlay y perdrait tout son sens.
    let sleepStages: [SleepStageInterval]

    /// `mode` et `indexSelectionne` sont liftés à la page parente
    /// (`DetailAnalyseBasaleVue`) pour que la `TimelineNuitsVue` puisse
    /// forcer la bascule vers la nuit tappée.
    init(
        nights: [NightChartData],
        mode: Binding<ModeAffichageGraphiqueBasale>,
        indexSelectionne: Binding<Int>,
        chargePour: @escaping (Date) -> SyntheseChargeContinue,
        sleepStages: [SleepStageInterval] = []
    ) {
        self.nights = nights
        self._mode = mode
        self._indexSelectionne = indexSelectionne
        self.chargePour = chargePour
        self.sleepStages = sleepStages
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            picker
            contenu
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(NiveauCarte.carte.forme)
    }

    // MARK: - Picker segmenté

    private var picker: some View {
        Picker("Mode d'affichage", selection: $mode) {
            ForEach(ModeAffichage.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: mode)
    }

    // MARK: - Bascule vue courante

    @ViewBuilder
    private var contenu: some View {
        if nights.isEmpty {
            etatVide
        } else {
            switch mode {
            case .toutes:
                VueGraphiqueToutes(nights: nights)
            case .parNuit:
                VueGraphiqueParNuit(
                    nights: nights,
                    indexSelectionne: $indexSelectionne,
                    chargePour: chargePour,
                    sleepStages: sleepStages
                )
            }
        }
    }

    private var etatVide: some View {
        ContentUnavailableView(
            "Aucune nuit à afficher",
            systemImage: "moon.zzz",
            description: Text("Le graphique apparaîtra dès qu'une nuit aura été analysée.")
        )
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
}

// MARK: - Vue agrégée « Toutes »

/// Affiche toutes les nuits en surimpression (gris léger), la tendance
/// moyenne (ambre), le repère lente moyen (💉 violet), et les events
/// (hypos / rapide / resucrage). L'axe X est scrollable horizontalement.
private struct VueGraphiqueToutes: View {

    let nights: [NightChartData]

    @State private var periode: PeriodeRepartition = .trois

    /// Popover lente moyenne (lifted ici pour clamp + zIndex max).
    @State private var presentedEventInfo: PresentedEventInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entete
                .padding(.top, 10)
            pickerPeriode
            chart
                .frame(height: 220)
                .padding(.top, 10)
                .padding(.bottom, 12)
                // Padding négatif asymétrique : touche le bord gauche,
                // garde ~4 pt entre l'axe Y et le bord droit du card.
                .padding(.leading, -20)
                .padding(.trailing, -16)
            Divider()
            LegendeGraphique()
                .padding(.top, 8)
        }
    }

    /// Titre + sous-titre — sous-titre indique combien de nuits ont
    /// effectivement été affichées sur la fenêtre temporelle choisie.
    private var entete: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Glycémie nocturne")
                .font(.title3.weight(.semibold))
            Text("\(nuitsFiltrees.count) nuits affichées · \(periode.labelLong)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Picker 3/7/14 j — aligné sur celui de `RepartitionNuitsVue`
    /// (même enum `PeriodeRepartition`). 14 j par défaut.
    private var pickerPeriode: some View {
        Picker("Période", selection: $periode) {
            ForEach(PeriodeRepartition.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: periode)
    }

/// Nuits du dataset restreintes à la fenêtre sélectionnée. Le
    /// filtre s'applique sur `nightChartData.date >= cutoff`.
    private var nuitsFiltrees: [NightChartData] {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -periode.rawValue, to: Date.now) ?? Date.now)
        return nights.filter { cal.startOfDay(for: $0.date) >= cutoff }
    }

    /// Tendance moyenne pré-calculée — extension sur `[NightChartData]`,
    /// puis lissée pour rester visuellement cohérente avec les nuits.
    private var tendance: [GlucosePoint] { lisser(nuitsFiltrees.tendanceMoyenne) }

    private var heureLente: Date? { nuitsFiltrees.heureLenteMoyenne }

    /// Bornes du domaine X — calées sur la première nuit filtrée pour
    /// garder l'alignement temporel avec `tendance` et `glucoseValues`.
    private var bornesX: (debut: Date, fin: Date)? {
        guard let p = nuitsFiltrees.first?.glucoseValues,
              let d = p.first?.time, let f = p.last?.time
        else { return nil }
        return (d, f)
    }

    /// Domaine visible initial : 22h00 → 6h00 (8h centrales sur les 10h).
    private var domaineVisibleInitial: Date? {
        guard let bornes = bornesX else { return nil }
        let cal = Calendar.current
        let jourDebut = cal.startOfDay(for: bornes.debut)
        return cal.date(bySettingHour: 22, minute: 0, second: 0, of: jourDebut)
    }

    /// Plage Y dynamique — cadrée sur la courbe de tendance (seule affichée),
    /// avec un padding de 10 mg/dL.
    private var plageY: ClosedRange<Double> {
        plageYAvecPadding(tendance.map(\.value))
    }

    @ViewBuilder
    private var chart: some View {
        if let bornes = bornesX {
            Chart {
                seuils
                courbeTendance
            }
            .chartXScale(domain: bornes.debut...bornes.fin)
            .chartYScale(domain: plageY)
            .chartXAxis { axeX }
            .chartYAxis { axeY }
            .chartPlotStyle { plotArea in
                plotArea.clipped()
            }
            // Lente moyenne rendue en pill via `EventsOnChart` —
            // même langage visuel que la vue Par nuit + popover
            // lifted pour clamp horizontal + zIndex max.
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotFrame = proxy.plotFrame {
                        let plotRect = geo[plotFrame]
                        ZStack {
                            // Tap-elsewhere → ferme le popover. Posé
                            // en fond du ZStack : les pills au-dessus
                            // captent leurs propres taps en priorité.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard presentedEventInfo != nil else { return }
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        presentedEventInfo = nil
                                    }
                                }
                            EventsOnChart(
                                events: lenteMoyenneEvent.map { [$0] } ?? [],
                                timeRange: bornes.debut...bornes.fin,
                                plotRect: plotRect,
                                presentedInfo: $presentedEventInfo,
                                enableTap: false
                            )
                            if let info = presentedEventInfo {
                                PopoverFlottant(info: info, plotRect: plotRect)
                                    .zIndex(200)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Synthétise un `NightEvent.lente` placé à l'heure moyenne des
    /// prises de lente sur la fenêtre filtrée — pill « Lente » (sans
    /// dose), l'idée est juste de signaler la prise.
    private var lenteMoyenneEvent: NightEvent? {
        guard let avgTime = nuitsFiltrees.heureLenteMoyenne else { return nil }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: avgTime)
        let h = String(format: "%dh%02d", comps.hour ?? 0, comps.minute ?? 0)
        return NightEvent(
            type: .lente,
            time: avgTime,
            value: 0,
            detail: "Lente à \(h)"
        )
    }

    // MARK: Marks

    /// Bande de cible + lignes de seuil, dans le style commun aux graphiques
    /// de l'app (`StyleGrapheGlycemie`). Les seuils viennent du profil : ils
    /// étaient figés à 70/180 ici et ne suivaient pas les réglages. Les
    /// annotations « 70 » et « 180 » disparaissent — l'axe Y les porte déjà,
    /// comme sur les graphiques repas et sport.
    @ChartContentBuilder
    private var seuils: some ChartContent {
        if let bornes = bornesX {
            StyleGrapheGlycemie.zoneCible(
                de: bornes.debut, a: bornes.fin,
                seuils: seuilsProfil
            )
        }
        StyleGrapheGlycemie.lignesSeuils(seuilsProfil)
    }

    private var seuilsProfil: SeuilsGlycemiques {
        ProfilService.shared.profil.seuilsGlycemiques
    }

    /// Tendance moyenne — découpée en segments hypo/normal/hyper pour
    /// que la portion sous 70 vire au rouge et celle au-dessus de 180
    /// vire à l'orange. La portion normale est en **violet** pour
    /// bien se distinguer des courbes individuelles grises.
    @ChartContentBuilder
    private var courbeTendance: some ChartContent {
        let segments = segmenter(tendance)
        ForEach(segments) { seg in
            ForEach(seg.points) { p in
                LineMark(
                    x: .value("Heure", p.time),
                    y: .value("Glycémie", p.value),
                    series: .value("Nuit", "tendance-\(seg.id.uuidString)")
                )
                .foregroundStyle(couleurSegment(seg.categorie, defaut: .basaleTendanceMoy))
                .lineStyle(StrokeStyle(lineWidth: StyleGrapheGlycemie.epaisseurCourbe))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    /// Axe X — labels horaires en français (« 22 h », « 0 h », « 3 h »),
    /// grille pointillée légère.
    ///
    /// La closure-form de `AxisValueLabel { ... }` (avec construction
    /// manuelle du `Text`) est utilisée plutôt que `AxisValueLabel(format:)`
    /// — la variante `format:` ignore `.foregroundStyle(.secondary)` et
    /// retombe sur le tint d'accent (bleu).
    @AxisContentBuilder
    private var axeX: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 1)) { value in
            AxisGridLine(stroke: StyleGrapheGlycemie.traitGrille)
                .foregroundStyle(.secondary.opacity(0.3))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date, format: .dateTime.hour().locale(Locale(identifier: "fr_FR")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Axe Y — uniquement les 3 seuils cliniques (hypo / cible /
    /// hyper). Pas de grid line — les RuleMarks 70/180 jouent ce rôle.
    /// Closure-form de `AxisValueLabel` pour que `.foregroundStyle(.secondary)`
    /// soit respecté (sinon le label retombe sur le tint d'accent bleu).
    @AxisContentBuilder
    private var axeY: some AxisContent {
        AxisMarks(position: .trailing, values: [70.0, 120.0, 180.0]) { value in
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text("\(Int(v))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Vue « Par nuit »

/// Affiche la nuit sélectionnée : entête (titre + chevrons + date picker) +
/// un `Chart` whole-night avec crosshair (long-press + drag), swipe gauche/
/// droite pour naviguer entre nuits, et pills d'events tappables (popover
/// détaillé).
private struct VueGraphiqueParNuit: View {

    let nights: [NightChartData]
    @Binding var indexSelectionne: Int
    let chargePour: (Date) -> SyntheseChargeContinue
    /// Stades de sommeil de la nuit affichée — voir doc sur
    /// `CourbesNocturnesChart.sleepStages`.
    var sleepStages: [SleepStageInterval] = []

    /// État courant du crosshair (long-press + drag sur la courbe) —
    /// `nil` quand le doigt est relâché.
    @State private var crosshairSelection: CrosshairSelection?

    /// Popover lifted ici (au lieu d'être attaché aux pills) → permet
    /// de le rendre toujours au premier plan (zIndex max) et de le
    /// clamper aux bords du plotRect pour qu'il reste dans la carte.
    @State private var presentedEventInfo: PresentedEventInfo?

    /// Sync avec `indexSelectionne` — DatePicker bind dessus, les
    /// `.onChange` traduisent dans les deux sens.
    @State private var selectedDate: Date = Date()

    /// Popover du calendrier — ouvert au tap sur le bouton date,
    /// fermé automatiquement dès qu'une date est sélectionnée.
    @State private var afficherCalendrier: Bool = false

    /// Incrémenté à chaque changement de nuit (chevron, swipe, calendrier)
    /// pour déclencher le retour haptique via `.sensoryFeedback(trigger:)`.
    @State private var compteurNavigation: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete
                .padding(.top, 10)
            chartFullNight()
                .frame(height: 220)
                .padding(.top, 10)
                .padding(.leading, -20)
                .padding(.trailing, -16)
                .gesture(swipeNavigation)
            if !intervallesVisibles.isEmpty {
                hypnogramme
                    .frame(height: 40)
                    .padding(.top, -6)
                    .padding(.leading, -20)
                    .padding(.trailing, -16)
                legendeSommeil
                    .padding(.top, 2)
            }
            Divider()
                .padding(.top, 2)
            CarteVerdictNuit(nuit: nuit, nights: nights, chargeSynthese: chargePour(nuit.date))
            Divider()
            DetailZonesNuit(nuit: nuit)
        }
        .sensoryFeedback(.selection, trigger: compteurNavigation)
        .onAppear {
            selectedDate = Calendar.current.startOfDay(for: nuit.date)
        }
        .onChange(of: indexSelectionne) { _, _ in
            let d = Calendar.current.startOfDay(for: nuit.date)
            if selectedDate != d { selectedDate = d }
        }
        .onChange(of: selectedDate) { _, newDate in
            let cal = Calendar.current
            let target = cal.startOfDay(for: newDate)
            if let idx = nights.firstIndex(where: {
                cal.startOfDay(for: $0.date) == target
            }), idx != indexSelectionne {
                withAnimation(.easeInOut(duration: 0.25)) {
                    indexSelectionne = idx
                }
            }
            if afficherCalendrier { afficherCalendrier = false }
        }
    }

    /// Helper utilisé par les couches du chartOverlay pour fermer le
    /// popover (tap-elsewhere). Animation cohérente avec la `transition`
    /// scale + opacity attachée au popover.
    private func dismissPopover() {
        guard presentedEventInfo != nil else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            presentedEventInfo = nil
        }
    }

    // MARK: - Helpers

    private var nuit: NightChartData {
        guard !nights.isEmpty else {
            fatalError("VueGraphiqueParNuit ne devrait pas être appelée sans nuits")
        }
        let safe = max(0, min(indexSelectionne, nights.count - 1))
        return nights[safe]
    }

    // MARK: Navigation entre nuits (chevrons + swipe)

    /// `nights` est trié plus récent d'abord (index 0 = dernière nuit) —
    /// index+1 = nuit plus ancienne, index-1 = nuit plus récente.
    private var indexPlusAncienne: Int? {
        let i = indexSelectionne + 1
        return i < nights.count ? i : nil
    }

    private var indexPlusRecente: Int? {
        let i = indexSelectionne - 1
        return i >= 0 ? i : nil
    }

    private func naviguer(vers index: Int) {
        withAnimation(.easeInOut(duration: 0.22)) {
            indexSelectionne = index
        }
        compteurNavigation += 1
    }

    /// Swipe horizontal sur le chart → nuit précédente/suivante. Coexiste
    /// avec le crosshair (long-press + drag) : un flick rapide dépasse le
    /// déplacement toléré par le `LongPressGesture` avant que ses 0.2 s ne
    /// s'écoulent, qui échoue alors et laisse ce geste ancêtre reconnaître
    /// le swipe — un doigt qui reste posé (scrub) déclenche le crosshair
    /// en premier, comme avant.
    private var swipeNavigation: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if value.translation.width < 0, let i = indexPlusRecente {
                    naviguer(vers: i)
                } else if value.translation.width > 0, let i = indexPlusAncienne {
                    naviguer(vers: i)
                }
            }
    }

    // MARK: Entête (titre + DatePicker compact)

    /// Plage acceptable par le DatePicker : bornée aux nuits du dataset
    /// → l'utilisateur ne peut pas sélectionner une date sans données.
    private var plageDatesNuits: ClosedRange<Date> {
        let cal = Calendar.current
        let dates = nights.map { cal.startOfDay(for: $0.date) }
        let min = dates.min() ?? Date()
        let max = dates.max() ?? Date()
        return min...max
    }

    /// Titre à gauche, bouton-calendrier tappable à droite. Le bouton
    /// ouvre un popover avec un DatePicker `.graphical` qui se ferme
    /// dès qu'une date est sélectionnée (contrairement au DatePicker
    /// `.compact` natif qui reste ouvert).
    private var entete: some View {
        HStack(spacing: 8) {
            Text("Glycémie nocturne")
                .font(.title3.weight(.semibold))
            Spacer()
            boutonDate
        }
    }

    private var boutonDate: some View {
        Button {
            afficherCalendrier = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                Text(libelleDateCompact)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $afficherCalendrier) {
            DatePicker(
                "Date",
                selection: $selectedDate,
                in: plageDatesNuits,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "fr_FR"))
            .padding()
            .frame(minWidth: 320, minHeight: 360)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var libelleDateCompact: String {
        selectedDate.formatted(.dateTime.day().month(.abbreviated)
            .locale(Locale(identifier: "fr_FR")))
    }

    /// Légende factuelle des stades affichés — seulement les stades
    /// réellement présents cette nuit-là, dans l'ordre biologique.
    private var legendeSommeil: some View {
        let ordre: [SleepStage] = [.awake, .rem, .core, .deep, .asleepGenerique, .inBed]
        let presents = ordre.filter { stade in intervallesVisibles.contains { $0.stage == stade } }
        return HStack(spacing: 12) {
            ForEach(presents, id: \.self) { stade in
                HStack(spacing: 4) {
                    Circle()
                        .fill(couleurStade(stade))
                        .frame(width: 7, height: 7)
                    Text(stade.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Carrousel chartZone

    /// Courbe de la nuit lissée — calculée une fois par render et
    /// réutilisée par `courbeWholeNight` + le crosshair (snap au point
    /// glycémie le plus proche).
    private var pointsLissesNuit: [GlucosePoint] { lisser(nuit.glucoseValues) }

    /// Plage Y dynamique cadrée sur les min/max de la nuit.
    private var plageY: ClosedRange<Double> {
        plageYAvecPadding(nuit.glucoseValues.map(\.value))
    }

    /// Domaine X du chart — de la première à la dernière mesure de la
    /// nuit (typ. 21 h → 7 h).
    private var totalNightRange: ClosedRange<Date> {
        let pts = nuit.glucoseValues
        let d = pts.first?.time ?? nuit.date
        let f = pts.last?.time ?? nuit.date
        return d...f
    }

    /// Chart unique **whole-night, full-width, sans scroll**. Affiche
    /// toute la nuit (21 h → 7 h) d'un coup dans la largeur disponible.
    /// Axe Y à droite (position trailing) avec valeurs adaptatives au
    /// min/max de la nuit.
    @ViewBuilder
    private func chartFullNight() -> some View {
        Chart {
            seuils
            courbeWholeNight
        }
        .chartXScale(domain: totalNightRange)
        .chartYScale(domain: plageY)
        .chartXAxis { axeXFullNight }
        .chartYAxis { axeYTrailingAdaptatif }
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let plotRect = geo[plotFrame]
                    ZStack {
                        // Couche fond : capte le long-press + drag pour
                        // alimenter le crosshair. Les pills par-dessus
                        // restent tappables (tap court < 200 ms).
                        CrosshairGestureLayer(
                            plotRect: plotRect,
                            timeRange: totalNightRange,
                            glucoseSeries: pointsLissesNuit,
                            selection: $crosshairSelection,
                            onTap: dismissPopover
                        )
                        EventsOnChart(
                            events: nuit.events,
                            timeRange: totalNightRange,
                            plotRect: plotRect,
                            presentedInfo: $presentedEventInfo
                        )
                        // Popover au-dessus de tout, clampé pour ne
                        // pas sortir du plotRect — toujours visible
                        // dans la carte même près des bords.
                        if let info = presentedEventInfo {
                            PopoverFlottant(info: info, plotRect: plotRect)
                                .zIndex(200)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.18),
                                           value: info.event.id)
                        }
                        if let sel = crosshairSelection {
                            CrosshairVisual(selection: sel, plotRect: plotRect)
                                .transition(.opacity)
                        }
                    }
                }
            }
        }
    }

    /// Axe Y posé à droite (`position: .trailing`) avec graduations
    /// adaptatives — ~4 labels « ronds » couvrant la plage Y réelle
    /// (step 10 / 20 / 25 / 50 / 100 selon l'amplitude).
    @AxisContentBuilder
    private var axeYTrailingAdaptatif: some AxisContent {
        AxisMarks(position: .trailing, values: axisYValuesAdaptatives) { value in
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text("\(Int(v))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// Valeurs Y adaptatives — cible ~4 graduations « rondes »
    /// couvrant la `plageY` courante.
    private var axisYValuesAdaptatives: [Double] {
        let bas = plageY.lowerBound
        let haut = plageY.upperBound
        let span = haut - bas
        guard span > 0 else { return [] }
        let target = 4.0
        let rawStep = span / target
        let niceSteps: [Double] = [10, 20, 25, 50, 100]
        let step = niceSteps.first(where: { $0 >= rawStep }) ?? 100
        let start = ceil(bas / step) * step
        var values: [Double] = []
        var v = start
        while v <= haut + 0.5 {
            values.append(v)
            v += step
        }
        return values
    }


    /// Courbe glycémique de **toute la nuit** (vs `courbeZone` qui se
    /// limitait à une zone). Segmentée hypo/normal/hyper pour la
    /// coloration des portions hors cible.
    @ChartContentBuilder
    private var courbeWholeNight: some ChartContent {
        let segments = segmenter(pointsLissesNuit)
        ForEach(segments) { seg in
            ForEach(seg.points) { p in
                LineMark(
                    x: .value("Heure", p.time),
                    y: .value("Glycémie", p.value),
                    series: .value("Seg", "nuit-\(seg.id.uuidString)")
                )
                .foregroundStyle(couleurSegment(seg.categorie, defaut: couleurCourbe))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    /// Axe X au pas 1 h — toute la nuit (10 h) tient dans la largeur
    /// du chart, donc 30 min serait trop dense (20 labels). Avec 1 h
    /// on a 10 labels — acceptable sur mobile.
    @AxisContentBuilder
    private var axeXFullNight: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 1)) { value in
            AxisGridLine(stroke: StyleGrapheGlycemie.traitGrille)
                .foregroundStyle(.secondary.opacity(0.3))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(formatH(date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// Format heure seule (« 22h », « 6h ») — pas de minutes car le pas
    /// d'axe est de 1 h, les minutes sont toujours « 00 ».
    private func formatH(_ date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        return "\(h)h"
    }

    // MARK: Marks partagés

    /// Même peau que les graphiques repas et sport — voir `StyleGrapheGlycemie`.
    @ChartContentBuilder
    private var seuils: some ChartContent {
        StyleGrapheGlycemie.zoneCible(
            de: totalNightRange.lowerBound, a: totalNightRange.upperBound,
            seuils: seuilsProfil
        )
        StyleGrapheGlycemie.lignesSeuils(seuilsProfil)
    }

    private var seuilsProfil: SeuilsGlycemiques {
        ProfilService.shared.profil.seuilsGlycemiques
    }

    /// Ordre d'affichage des stades, de haut (éveil) en bas (au lit) —
    /// même convention que le hypnogramme de l'app Santé d'Apple.
    private var ordreHypnogramme: [SleepStage] {
        [.awake, .rem, .core, .deep, .asleepGenerique, .inBed]
    }

    /// Frise horizontale **distincte** de la courbe glycémique — une barre
    /// par stade présent, empilées de haut (éveil) en bas (au lit), sur le
    /// même axe temporel. Séparée du chart glycémie (plutôt qu'en bandes
    /// translucides derrière la courbe, essayé d'abord) parce que 6 teintes
    /// superposées à la courbe la rendaient illisible.
    @ViewBuilder
    private var hypnogramme: some View {
        let presents = ordreHypnogramme.filter { stade in intervallesVisibles.contains { $0.stage == stade } }
        Chart {
            ForEach(intervallesVisibles) { intervalle in
                RectangleMark(
                    xStart: .value("Début", max(intervalle.debut, totalNightRange.lowerBound)),
                    xEnd: .value("Fin", min(intervalle.fin, totalNightRange.upperBound)),
                    y: .value("Stade", intervalle.stage.label),
                    height: .ratio(0.75)
                )
                .foregroundStyle(couleurStade(intervalle.stage))
            }
        }
        .chartXScale(domain: totalNightRange)
        .chartYScale(domain: presents.reversed().map(\.label))
        .chartXAxis(.hidden)
        // Axe trailing invisible mais réservé à la même largeur que celui du
        // chart de glycémie juste au-dessus (`axeYTrailingAdaptatif`, labels
        // à 3 chiffres) — sans ça les deux plots n'ont pas la même largeur
        // utile et la frise déborde par rapport à la courbe.
        .chartYAxis {
            AxisMarks(position: .trailing, values: [presents.first?.label ?? "?"]) { _ in
                AxisValueLabel {
                    Text("000")
                        .font(.caption2)
                        .foregroundStyle(.clear)
                        .monospacedDigit()
                }
            }
        }
    }

    private var intervallesVisibles: [SleepStageInterval] {
        sleepStages.filter { $0.fin > totalNightRange.lowerBound && $0.debut < totalNightRange.upperBound }
    }

    private func couleurStade(_ stade: SleepStage) -> Color {
        switch stade {
        case .awake:           return .orange
        case .rem:              return .mint
        case .core:              return .blue
        case .deep:               return .indigo
        case .asleepGenerique:    return .blue
        case .inBed:              return .gray
        }
    }

    private var couleurCourbe: Color {
        colorScheme == .dark ? .basaleCourbeNuitDark : .basaleCourbeNuit
    }

    /// Format strict « HH:MM » zéro-padded — `.dateTime.hour().minute()`
    /// en fr_FR donne « 1:00 » sans zéro, on force le padding pour
    /// rester aligné colonne.
    private func formatHHMM(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

}

// MARK: - Carte verdict de la nuit (sous le graphe « Par nuit »)

/// Verdict factuel de la nuit sélectionnée — badge de catégorie, **dérive
/// nette** de la nuit profonde en mg/dL (l'unité de décision, comparable au
/// seuil ±30) et jauge de position dans la zone de stabilité. Répond au
/// « qu'a conclu l'app sur cette nuit ? » sans laisser l'utilisateur
/// interpréter une pente horaire.
private struct CarteVerdictNuit: View {

    let nuit: NightChartData
    /// Toutes les nuits du dataset — nécessaires au pied de carte pour
    /// afficher les vraies nuits retenues (chacune colorée par sa catégorie).
    var nights: [NightChartData] = []
    /// Charge d'activité de la semaine précédant cette nuit — contexte
    /// corrélé au verdict, jamais présenté comme cause (dette technique B1,
    /// doc Eraser « B1 — Détection basale », V2 priorité haute).
    var chargeSynthese: SyntheseChargeContinue? = nil

    /// Seuil de stabilité (± mg/dL) — même source que le calculateur.
    private let seuil = CalculAnalyseBasale.seuilDeriveStableParDefaut
    /// Demi-étendue de la jauge (± mg/dL). Le point est clampé aux bords ;
    /// la valeur affichée reste la vraie dérive.
    private let etendue: Double = 60
    /// Nb de nuits valides pilotant le verdict global (pied de carte).
    private let nuitsRecence = ConfigBasale().nuitsRecence

    var body: some View {
        if let z3 = zone3 {
            VStack(alignment: .leading, spacing: 0) {
                Text("Verdict de la nuit")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)

                if z3.isAnalyzed, let s = z3.slope {
                    verdictAnalyse(z3, slope: s)
                } else {
                    verdictExclu(z3)
                }

                if let chargeSynthese, let libelle = libelleCharge(chargeSynthese) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(couleurCharge(chargeSynthese))
                        Text(libelle)
                            .font(.caption)
                            .foregroundStyle(couleurCharge(chargeSynthese))
                    }
                    .padding(.top, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// `nil` si tendance stable (rien à signaler) ou pas assez de recul.
    private func libelleCharge(_ synthese: SyntheseChargeContinue) -> String? {
        switch synthese.tendance {
        case .enBaisse(let jours): return "Charge d'activité en baisse depuis \(jours)j"
        case .enHausse(let jours): return "Charge d'activité en hausse depuis \(jours)j"
        case .stable: return nil
        }
    }

    private func couleurCharge(_ synthese: SyntheseChargeContinue) -> Color {
        switch synthese.tendance {
        case .enBaisse: return .red
        case .enHausse: return .blue
        case .stable: return .secondary
        }
    }

    // MARK: Sous-vues

    /// Variante nominale : badge + dérive en gros, jauge, détail, poids.
    /// Hiérarchie du badge : **rechute > série > prolongée > hypo > dérive**
    /// — une nuit avec hypo profonde (zones 3+4) ne s'affiche jamais
    /// « Stable », même si la régression est plate (la stabilité viendrait
    /// du resucrage ou de la contre-régulation, pas de la basale).
    @ViewBuilder
    private func verdictAnalyse(_ z: ZoneData, slope: Double) -> some View {
        let derive = slope * heures(z)
        // Catégorie affichée = celle du verdict réel (`nuit.categorieVerdict`,
        // calculée par `evaluerZone3` avec la courbe complète), pas un recalcul
        // local sur la seule dérive — sinon une nuit qui frôle sans jamais
        // atteindre l'hypo/l'hyper se retrouve « Descendante » ici alors que
        // le verdict global la compte « Stable ».
        let categorie = nuit.categorieVerdict ?? CalculAnalyseBasale.categorie(deriveMgDl: derive, seuil: seuil)

        HStack(alignment: .center) {
            badgePrincipal(categorieDerive: categorie)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(deriveFmt(derive))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(categorie == .stable ? Color.primary : couleur(categorie))
                Text("mg/dL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 14)

        jauge(derive: derive, couleur: couleur(categorie))
            .padding(.bottom, 14)

        // Le fait de mesure en texte lisible (la dérive chiffrée est déjà en
        // héros au-dessus, inutile de la répéter ici).
        VStack(alignment: .leading, spacing: 3) {
            Text("Mesuré de \(hhmm(z.timeRange.lowerBound)) à \(hhmm(z.timeRange.upperBound)), soit \(dureeFmt(z)).")
                .foregroundStyle(.primary)
            Text(phraseSignal(derive: derive, categorieDerive: categorie))
                .foregroundStyle(aSignalHypo ? Color.red : Color.secondary)
        }
        .font(.system(size: 14))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 14)

        if !aSignalHypo, hyposEndormissement > 0 {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Hypo à l'endormissement — plutôt dîner ou bolus que basale, hors verdict")
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 14)
        }

        if aSignalHypo {
            blocRetenues(libelle: "tendance basse", couleur: .red)
        } else {
            blocRetenues(libelle: libelle(categorie).lowercased(), couleur: couleur(categorie))
        }
    }

    /// Variante exclue : badge + motif, pas de jauge (aucun signal retenu).
    /// Les hypos restent affichées même exclue — le signal vital ne
    /// disparaît pas avec l'exclusion de la pente.
    @ViewBuilder
    private func verdictExclu(_ z: ZoneData) -> some View {
        HStack(alignment: .top) {
            badge(texte: "Exclue", systemImage: "xmark.circle.fill", couleur: .orange)
            Spacer()
            if let raison = z.exclusionReason {
                Text(raison)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.bottom, 10)

        let hypos = bilan.episodesProfonds
        if hypos > 0 {
            Text("\(hypos) passage\(hypos > 1 ? "s" : "") < 70 malgré l'exclusion")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.bottom, 10)
        }

        blocRetenues(libelle: "exclue", couleur: .orange)
    }

    /// Jauge horizontale : bande verte = zone stable ±seuil, trait central
    /// = 0, point = dérive de la nuit (clampé aux bords de l'étendue).
    private func jauge(derive: Double, couleur: Color) -> some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let w = geo.size.width
                let clampee = min(max(derive, -etendue), etendue)
                let posX = w * (clampee + etendue) / (etendue * 2)
                let largeurBande = w * seuil / etendue
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)
                    Capsule()
                        .fill(Color.green.opacity(0.28))
                        .frame(width: largeurBande, height: 8)
                        .offset(x: (w - largeurBande) / 2)
                    Rectangle()
                        .fill(.tertiary)
                        .frame(width: 1, height: 14)
                        .offset(x: w / 2)
                    Circle()
                        .fill(couleur)
                        .frame(width: 15, height: 15)
                        .overlay(
                            Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2)
                        )
                        .offset(x: posX - 7.5)
                }
                .frame(height: 15)
            }
            .frame(height: 15)

            HStack {
                Text("−\(Int(etendue))")
                Spacer()
                Text("−\(Int(seuil))")
                Spacer()
                Text("0")
                Spacer()
                Text("+\(Int(seuil))")
                Spacer()
                Text("+\(Int(etendue))")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }

    /// Badge de tête — le danger prime, du plus urgent au moins urgent :
    /// rechute (sous-correction) > série (rase le seuil) > prolongée (ne
    /// remonte pas) > hypo simple > dérive.
    @ViewBuilder
    private func badgePrincipal(categorieDerive: CategorieNuit) -> some View {
        if bilan.rechutes > 0 {
            badge(texte: "Hypo avec rechute", systemImage: "exclamationmark.triangle.fill", couleur: .red)
        } else if bilan.enSerie > 0 {
            badge(texte: "Hypos en série", systemImage: "exclamationmark.triangle.fill", couleur: .red)
        } else if bilan.prolongees > 0 {
            badge(texte: "Hypo prolongée", systemImage: "exclamationmark.triangle.fill", couleur: .red)
        } else if bilan.episodesProfonds > 0 {
            badge(texte: bilan.episodesProfonds > 1 ? "\(bilan.episodesProfonds) hypos nocturnes" : "Hypo nocturne",
                  systemImage: "exclamationmark.triangle.fill", couleur: .red)
        } else {
            badgeCategorie(categorieDerive)
        }
    }

    private func badgeCategorie(_ c: CategorieNuit) -> some View {
        let (icone, teinte): (String, Color) = switch c {
        case .stable:        ("checkmark.circle.fill", .green)
        case .tendanceHaute: ("arrow.up.right", .orange)
        case .tendanceBasse: ("arrow.down.right", .red)
        }
        return badge(texte: libelle(c), systemImage: icone, couleur: teinte)
    }

    private func badge(texte: String, systemImage: String, couleur: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(texte)
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(couleur)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(couleur.opacity(0.13), in: Capsule())
    }

    /// Pied de carte « points honnêtes » : à gauche la place de cette nuit
    /// dans le verdict, à droite les **vraies** nuits retenues (fenêtre de
    /// récence), chronologiques, chacune colorée par sa propre catégorie —
    /// la nuit affichée est entourée d'un anneau. D'un coup d'œil : la
    /// composition du verdict (ex. 4 vertes + 1 rouge) et où se situe cette
    /// nuit. Une nuit hors fenêtre l'affiche explicitement (aucun anneau).
    /// Encart détaché : le poids de la nuit dans le verdict est une
    /// information d'une autre nature que la mesure elle-même. Empilé en
    /// petit sous le reste, il se noyait ; dans son propre bloc, il se lit.
    private func blocRetenues(libelle: String, couleur: Color) -> some View {
        let retenues = nights.filter(\.retenueDansVerdict).sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 12) {
            // Le compte vit dans la phrase plutôt qu'à l'opposé de la ligne :
            // en grande taille de texte, les deux bouts finissaient collés
            // aux bords de l'encart.
            VStack(alignment: .leading, spacing: 2) {
                Text("Dans le verdict")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(phraseRang(libelle: libelle, couleur: couleur, retenues: retenues))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            segmentsRetenues(retenues)

            if let legende = legendeRetenues {
                Text(legende)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « Nuit stable, 2ᵉ des 5 retenues » — le rang situe la nuit dans la
    /// fenêtre sans qu'on ait à compter les marques soi-même.
    private func phraseRang(libelle: String, couleur: Color, retenues: [NightChartData]) -> AttributedString {
        let colore = { (texte: String) -> AttributedString in
            var s = AttributedString(texte)
            s.foregroundColor = couleur
            s.font = .body.weight(.medium)
            return s
        }
        guard nuit.retenueDansVerdict,
              let rang = retenues.firstIndex(where: { $0.id == nuit.id }).map({ $0 + 1 }) else {
            return AttributedString("Hors de la fenêtre — \(retenues.count) nuits retenues sur \(nuitsRecence)")
        }
        var phrase = AttributedString("Nuit ")
        phrase += colore(libelle)
        phrase += AttributedString(", \(rang)\(rang == 1 ? "ʳᵉ" : "ᵉ") des \(nuitsRecence) retenues")
        return phrase
    }

    /// Cinq segments de largeur égale — ils occupent toute la largeur quelle
    /// que soit la taille du texte, là où des points serrés à gauche laissaient
    /// l'encart à moitié vide. Seuls les segments remplis portent une date :
    /// les slots libres n'ont rien à dire, le compte de la phrase suffit.
    private func segmentsRetenues(_ retenues: [NightChartData]) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<nuitsRecence, id: \.self) { i in
                    segment(retenues.indices.contains(i) ? retenues[i] : nil)
                }
            }
            HStack(spacing: 5) {
                ForEach(0..<nuitsRecence, id: \.self) { i in
                    let n = retenues.indices.contains(i) ? retenues[i] : nil
                    Text(n.map { jourCourt($0.date) } ?? " ")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(n?.id == nuit.id ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func segment(_ n: NightChartData?) -> some View {
        let estCourante = n?.id == nuit.id
        return Capsule()
            .fill(n?.categorieVerdict.map(couleur) ?? Color(.systemFill))
            .frame(height: 9)
            .frame(maxWidth: .infinity)
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(estCourante ? 0.55 : 0), lineWidth: 1.5)
                    .padding(-3)
            }
    }


    private func jourCourt(_ date: Date) -> String {
        Calendar.current.component(.day, from: date).formatted()
    }

    /// Ligne sous les points : combien de nuits ont été écartées entre la
    /// première et la dernière retenue. Compté plutôt qu'énuméré — lister les
    /// jours (« les 18, 19, 20, 21, 22, 23, 24, 25, 26 exclus ») débordait sur
    /// deux lignes dès que la fenêtre était trouée.
    private var legendeRetenues: String? {
        let cal = Calendar.current
        let retenues = nights.filter(\.retenueDansVerdict).sorted { $0.date < $1.date }
        guard let premiere = retenues.first?.date, let derniere = retenues.last?.date else {
            return nil
        }
        let ecartees = nights.filter {
            !$0.retenueDansVerdict && $0.date > premiere && $0.date < derniere
        }.count
        guard ecartees > 0 else { return nil }
        let j1 = cal.component(.day, from: premiere)
        let j2 = derniere.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
        return "\(ecartees) nuit\(ecartees > 1 ? "s" : "") écartée\(ecartees > 1 ? "s" : "") entre le \(j1) et le \(j2)"
    }

    // MARK: Logique d'affichage

    private var zone3: ZoneData? {
        nuit.zones.first(where: { $0.zone == .nuitProfonde })
    }

    /// Taxonomie hypos de la nuit (fenêtre de sommeil complète, zone 4 incluse).
    private var bilan: BilanHyposNuit { nuit.bilanHypos }

    /// Un signal hypo qui pilote badge/phrase/pied (zones 3+4 ou rechute).
    private var aSignalHypo: Bool {
        bilan.episodesProfonds > 0 || bilan.rechutes > 0
    }

    /// Hypos de la zone 2 — signal dîner/bolus, pas basale : averti sans
    /// faire basculer le verdict de la nuit.
    private var hyposEndormissement: Int {
        bilan.episodes - bilan.episodesProfonds
    }

    /// Phrase sous le détail — remplacée par le signal hypo quand il y en a
    /// un (la position vs seuil devient secondaire). Décrit la composition
    /// (série / prolongée) et le mode de remontée (resucrage vs spontanée,
    /// déduit du log repas).
    private func phraseSignal(derive: Double, categorieDerive: CategorieNuit) -> String {
        if bilan.rechutes > 0 {
            return "Resucrage suivi d'une nouvelle hypo — signal prioritaire, la dérive ne compte pas"
        }
        guard aSignalHypo else { return phrasePosition(derive) }

        var composition = "\(bilan.episodes) passage\(bilan.episodes > 1 ? "s" : "") < 70"
        if bilan.enSerie > 0 { composition += ", dont \(bilan.enSerie) en série" }
        if bilan.prolongees > 0 {
            composition += ", dont \(bilan.prolongees) prolongée\(bilan.prolongees > 1 ? "s" : "")"
        }

        let remontee: String
        if bilan.resucrees == 0 {
            remontee = bilan.episodes > 1
                ? "remontées spontanées, sans resucrage enregistré"
                : "remontée spontanée, sans resucrage enregistré"
        } else if bilan.spontanees == 0 {
            remontee = "stabilité obtenue par resucrage"
        } else {
            remontee = "\(bilan.resucrees) resucrée\(bilan.resucrees > 1 ? "s" : ""), \(bilan.spontanees) spontanée\(bilan.spontanees > 1 ? "s" : "")"
        }

        if categorieDerive == .stable {
            return "Courbe globalement stable, mais \(composition) — \(remontee)"
        }
        return "\(composition) — \(remontee)"
    }

    private func couleur(_ c: CategorieNuit) -> Color {
        switch c {
        case .stable:        return .green
        case .tendanceHaute: return .orange
        case .tendanceBasse: return .red
        }
    }

    private func libelle(_ c: CategorieNuit) -> String {
        switch c {
        case .stable:        return "Stable"
        case .tendanceHaute: return "Ascendante"
        case .tendanceBasse: return "Descendante"
        }
    }

    /// Phrase de position vs le seuil — explicite les cas limites (« à
    /// 3 mg/dL du seuil ») pour qu'une nuit borderline ne se lise pas
    /// comme une nuit franchement déviante, et inversement.
    private func phrasePosition(_ derive: Double) -> String {
        let absD = abs(derive)
        let seuilTxt = "±\(Int(seuil))"
        if absD <= seuil {
            let marge = seuil - absD
            if marge <= 10 {
                return "À \(Int(marge.rounded())) mg/dL du seuil (\(seuilTxt)) — limite, mais stable"
            }
            return "Bien dans la zone de stabilité (\(seuilTxt))"
        }
        let depassement = absD - seuil
        let sens = derive > 0 ? "au-dessus du" : "sous le"
        if depassement <= 15 {
            return "Juste \(sens) seuil (\(seuilTxt))"
        }
        return "Nettement \(sens) seuil (\(seuilTxt))"
    }

    // MARK: Formatage

    private func heures(_ z: ZoneData) -> Double {
        z.timeRange.upperBound.timeIntervalSince(z.timeRange.lowerBound) / 3600
    }

    private func dureeFmt(_ z: ZoneData) -> String {
        let mins = Int(z.timeRange.upperBound.timeIntervalSince(z.timeRange.lowerBound) / 60)
        return "\(mins / 60) h \(String(format: "%02d", mins % 60))"
    }

    private func deriveFmt(_ d: Double) -> String {
        String(format: "%+d", Int(d.rounded()))
    }

    private func plage(_ range: ClosedRange<Date>) -> String {
        "\(hhmm(range.lowerBound))–\(hhmm(range.upperBound))"
    }

    private func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02dh%02d", c.hour ?? 0, c.minute ?? 0)
    }

}

// MARK: - Détail des zones de la nuit (sous le graphe « Par nuit »)

/// Décompose la nuit en ses 4 zones et explicite, pour chacune, si elle
/// entre dans le calcul de la basale et pourquoi. Surface le « pourquoi »
/// par nuit demandé : statut (analysée / contexte / exclue + motif) et,
/// pour la nuit profonde, la pente retenue.
private struct DetailZonesNuit: View {

    let nuit: NightChartData

    /// Repliée par défaut — le détail zone par zone est secondaire face à
    /// la carte verdict juste au-dessus, qui porte déjà l'essentiel.
    @State private var deplie = false

    var body: some View {
        DisclosureGroup(isExpanded: $deplie) {
            if nuit.zones.isEmpty {
                Text("Aucune zone calculée pour cette nuit — lente non enregistrée ou données insuffisantes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(nuit.zones) { zone in
                        ligneZone(zone)
                    }
                }
                .padding(.top, 8)
            }
        } label: {
            Text("Zones de la nuit")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func ligneZone(_ z: ZoneData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: z.zone.icone)
                .font(.body)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(z.zone.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(plage(z.timeRange))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            statut(z)
        }
        .padding(.vertical, 2)
    }

    /// Pastille de statut à droite — contexte / analysée / exclue. Le
    /// chiffre de dérive de la nuit profonde vit dans `CarteVerdictNuit`
    /// (pas de doublon ici).
    @ViewBuilder
    private func statut(_ z: ZoneData) -> some View {
        if z.zone == .preEndormissement || z.zone == .dawnPhenomenon {
            badge(systemImage: "circle.dashed", texte: "Contexte", couleur: .secondary)
        } else if z.isAnalyzed {
            badge(systemImage: "checkmark.circle.fill", texte: "Analysée", couleur: .green)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                badge(systemImage: "xmark.circle.fill", texte: "Exclue", couleur: .orange)
                if let raison = z.exclusionReason {
                    Text(raison)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func badge(systemImage: String, texte: String, couleur: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(texte)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(couleur)
    }

    // MARK: Formatage

    private func plage(_ range: ClosedRange<Date>) -> String {
        "\(hhmm(range.lowerBound))–\(hhmm(range.upperBound))"
    }

    private func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02dh%02d", c.hour ?? 0, c.minute ?? 0)
    }

}

// MARK: - EventsOnChart (overlay events sur le chart Par nuit)

/// Overlay posé en `chartOverlay` sur `chartPourZone`. Rend deux
/// couches superposées :
///
///   1. **Lignes pointillées verticales** sur toute la hauteur du
///      plot area (de plotRect.minY à plotRect.maxY), colorées selon
///      le type d'event (opacité 0.4).
///   2. **Pills** au sommet du plot area (level 0 à ~14 pt du haut,
///      level 1 à ~38 pt pour les overlaps), tappables.
///
/// Logique de groupement :
///   - 2 events à moins de 30 min : la 2e pill descend en level 1
///   - ≥ 3 events dans une fenêtre de 30 min : pill multi-événement
///     (« 💉 1.5u · 🍬 15g »), fond neutre `.secondary.opacity(0.18)`
///
/// Tap sur une pill → `PopoverEventDetail` sous la pill (auto-dismiss
/// 4 s, re-tap toggle).
// MARK: - CrosshairOverlay (hover/drag pour lire la valeur glycémie)

/// Overlay style « Bourse » : un `DragGesture(minimumDistance: 0)`
/// capte la position du doigt sur le plot area et publie via le
/// binding `selection` la valeur la plus proche (date + glycémie).
///
/// La vue ne dessine PAS la ligne verticale ni la bulle — c'est le
/// parent qui les rend, par-dessus l'overlay, pour qu'elles puissent
/// déborder hors du plotRect (la bulle remonte au-dessus du chart).
private struct CrosshairGestureLayer: View {

    let plotRect: CGRect
    let timeRange: ClosedRange<Date>
    let glucoseSeries: [GlucosePoint]
    @Binding var selection: CrosshairSelection?
    /// Tap court (non-pill, non-long-press) → dismiss popover parent.
    /// Pills d'events captent leurs propres taps en priorité (couche
    /// supérieure dans le ZStack du chartOverlay).
    var onTap: () -> Void = {}

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            // LongPress avant Drag → un tap simple n'active pas le
            // crosshair (les pills d'events restent tappables). Seul
            // un appui ~200 ms active la lecture de courbe.
            .gesture(
                LongPressGesture(minimumDuration: 0.2)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        if case .second(_, let drag?) = value {
                            updateSelection(at: drag.location)
                        }
                    }
                    .onEnded { _ in
                        selection = nil
                    }
            )
            .simultaneousGesture(TapGesture().onEnded { onTap() })
    }

    private func updateSelection(at point: CGPoint) {
        let xInPlot = point.x - plotRect.origin.x
        guard xInPlot >= 0, xInPlot <= plotRect.width else {
            selection = nil
            return
        }
        // Convertit la position X relative en `Date` (linéaire sur
        // la `timeRange`).
        let frac = xInPlot / plotRect.width
        let span = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound)
        let date = timeRange.lowerBound.addingTimeInterval(Double(frac) * span)
        // Cherche le sample glycémie le plus proche dans le temps.
        guard let nearest = glucoseSeries.min(by: {
            abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date))
        }) else {
            selection = nil
            return
        }
        // Re-positionne le crosshair à l'X du sample exact pour que
        // la ligne et la bulle « snap » au point de la courbe.
        let exactFrac = nearest.time.timeIntervalSince(timeRange.lowerBound) / span
        let exactX = plotRect.origin.x + CGFloat(exactFrac) * plotRect.width
        selection = CrosshairSelection(
            x: exactX,
            time: nearest.time,
            value: nearest.value
        )
    }
}

/// État courant du crosshair : position X (dans le repère parent du
/// chartOverlay) + temps + valeur glycémie.
private struct CrosshairSelection: Equatable {
    let x: CGFloat
    let time: Date
    let value: Double
}

/// Ligne verticale + bulle valeur, posées par-dessus l'overlay.
private struct CrosshairVisual: View {
    let selection: CrosshairSelection
    let plotRect: CGRect

    var body: some View {
        // Ligne verticale full-height (sur plot area)
        Rectangle()
            .fill(Color.secondary.opacity(0.55))
            .frame(width: 1, height: plotRect.height)
            .position(x: selection.x, y: plotRect.midY)

        // Bulle valeur — posée au sommet du plot area, clampée
        // horizontalement pour ne pas sortir.
        ValueBubble(value: selection.value, time: selection.time)
            .fixedSize()
            .background(
                GeometryReader { bg in
                    Color.clear
                        .preference(key: BubbleWidthKey.self, value: bg.size.width)
                }
            )
            .position(x: clampedX(),
                      y: plotRect.minY + 22)
    }

    /// Empêche la bulle de déborder de plotRect.
    private func clampedX() -> CGFloat {
        let estW: CGFloat = 110
        return max(plotRect.minX + estW / 2,
                   min(plotRect.maxX - estW / 2, selection.x))
    }
}

private struct BubbleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ValueBubble: View {
    let value: Double
    let time: Date

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Int(value)) mg/dL")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(couleur)
            Text(timeStr)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
    }

    private var timeStr: String {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Colore la valeur en miroir des 3 couleurs de segments de la
    /// courbe : <70 = hypo (rouge), >180 = hyper (orange), sinon le
    /// gris « in-range » utilisé par le segment principal (couleur
    /// auto-adaptée clair/sombre).
    private var couleur: Color {
        if value < 70 { return .basaleHypo }
        if value > 180 { return .basaleHyper }
        return colorScheme == .dark ? .basaleCourbeNuitDark : .basaleCourbeNuit
    }
}

private struct EventsOnChart: View {

    let events: [NightEvent]
    let timeRange: ClosedRange<Date>
    let plotRect: CGRect

    /// Liftée au parent : permet de rendre le popover au-dessus de
    /// tout (zIndex max) et de le clamper aux bords du plotRect pour
    /// qu'il reste toujours visible dans la carte.
    @Binding var presentedInfo: PresentedEventInfo?

    /// Active/désactive le tap → popover. Vue Toutes passe `false` sur
    /// la pill « Lente » (info synthétique sans détail utile au tap).
    var enableTap: Bool = true

    /// Largeur estimée d'une pill standard (« 💉 1.5u », « 🍬 15g »…)
    /// — sert au calcul de collision pixel-à-pixel.
    private static let pillEstimatedWidth: CGFloat = 64
    /// Gap minimum (en pt) entre deux pills sur le même level.
    private static let pillGap: CGFloat = 4
    /// Décalage vertical entre deux levels successifs.
    static let levelStep: CGFloat = 24
    /// Y de base (level 0) — partagée avec le parent pour positionner
    /// le popover.
    static let baseY: CGFloat = 14

    var body: some View {
        let positioned = computePositions()
        ZStack(alignment: .topLeading) {
            // Couche 1 : lignes pointillées full-height (en dessous des pills)
            ForEach(positioned) { item in
                Path { p in
                    let x = plotRect.origin.x + item.x
                    p.move(to: CGPoint(x: x, y: plotRect.origin.y))
                    p.addLine(to: CGPoint(x: x, y: plotRect.origin.y + plotRect.height))
                }
                .stroke(lineColor(for: item),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Couche 2 : pills tappables au sommet (sans popover —
            // rendu au niveau parent pour clamping + zIndex max).
            // `enableTap = false` → pill statique sans handler.
            ForEach(positioned) { item in
                EventPillTappable(
                    item: item,
                    onTap: enableTap ? { handleTap(item) } : nil
                )
                .position(
                    x: plotRect.origin.x + item.x,
                    y: plotRect.origin.y + Self.pillYForLevel(item.level)
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: timeRange.lowerBound)
        .animation(.easeInOut(duration: 0.2), value: events.map(\.id))
    }

    /// Centre Y d'une pill selon son level — exposé `static` pour que
    /// le parent puisse calculer la position du popover.
    static func pillYForLevel(_ level: Int) -> CGFloat {
        baseY + CGFloat(level) * levelStep
    }

    private func lineColor(for item: PositionedEvent) -> Color {
        switch item.rendering {
        case .single(let e):  return e.type.pillForeground.opacity(0.4)
        case .multi:          return .secondary.opacity(0.4)
        }
    }

    private func handleTap(_ item: PositionedEvent) {
        guard case .single(let event) = item.rendering else { return }
        // Toggle si la même pill est re-tappée → dismiss animé.
        if presentedInfo?.event.id == event.id {
            withAnimation(.easeInOut(duration: 0.18)) {
                presentedInfo = nil
            }
            return
        }
        // Publie position absolue (incl. plotRect.origin) pour que
        // le parent puisse positionner+clamper le popover.
        let absX = plotRect.origin.x + item.x
        let absY = plotRect.origin.y + Self.pillYForLevel(item.level)
        let newInfo = PresentedEventInfo(event: event, pillX: absX, pillY: absY)
        // Première apparition (rien d'affiché) → fade+scale via la
        // transition. Switch d'une bulle à l'autre → snap instantané,
        // pas d'animation entre les deux.
        if presentedInfo == nil {
            withAnimation(.easeInOut(duration: 0.18)) {
                presentedInfo = newInfo
            }
        } else {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                presentedInfo = newInfo
            }
        }
        let snapId = event.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if presentedInfo?.event.id == snapId {
                withAnimation(.easeInOut(duration: 0.18)) {
                    presentedInfo = nil
                }
            }
        }
    }

    // MARK: - Calcul positions + détection collision pixel

    /// Algorithme de placement « stack the lowest available level » :
    /// pour chaque event trié par X, on cherche le premier level dont
    /// le bord droit de la dernière pill placée laisse assez de place
    /// (gap inclus) pour insérer cette pill sans chevauchement
    /// horizontal. Si aucun level n'est disponible, on en ouvre un
    /// nouveau. Résultat : N levels dynamiques, jamais de superposition.
    private func computePositions() -> [PositionedEvent] {
        let inRange = events
            .filter { timeRange.contains($0.time) }
            .sorted { $0.time < $1.time }

        // levelRightEdge[i] = X du bord droit de la dernière pill
        // placée au level i (en pt). Permet de tester en O(1) si la
        // nouvelle pill peut s'insérer.
        var levelRightEdge: [CGFloat] = []
        var result: [PositionedEvent] = []
        let halfPill = Self.pillEstimatedWidth / 2

        for event in inRange {
            let x = xForTime(event.time)
            let leftEdge = x - halfPill

            // Cherche le premier level où la pill peut s'insérer.
            var assignedLevel = -1
            for (i, edge) in levelRightEdge.enumerated() {
                if leftEdge >= edge + Self.pillGap {
                    assignedLevel = i
                    break
                }
            }
            if assignedLevel == -1 {
                levelRightEdge.append(0)
                assignedLevel = levelRightEdge.count - 1
            }
            levelRightEdge[assignedLevel] = x + halfPill

            result.append(PositionedEvent(
                id: event.id,
                rendering: .single(event),
                x: x,
                level: assignedLevel
            ))
        }
        return result
    }

    /// Position X relative au plot area (0 = gauche du plot,
    /// plotRect.width = droite du plot).
    private func xForTime(_ date: Date) -> CGFloat {
        let span = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound)
        guard span > 0 else { return 0 }
        let offset = date.timeIntervalSince(timeRange.lowerBound)
        let frac = max(0, min(1, offset / span))
        return plotRect.width * CGFloat(frac)
    }
}

/// Info publiée par `EventsOnChart` au parent quand une pill est
/// tappée — sert à rendre le popover au-dessus de tout (zIndex max)
/// et à le clamper aux bords du card.
struct PresentedEventInfo: Equatable {
    let event: NightEvent
    let pillX: CGFloat   // position absolue dans le repère du chartOverlay
    let pillY: CGFloat
}

/// Popover rendu au niveau du parent (pas attaché à la pill) avec :
/// 1. Mesure de sa propre taille via PreferenceKey
/// 2. Position X clampée entre les bords du plotRect → toujours visible
/// 3. Position Y juste sous la pill (anchor = pill bottom)
private struct PopoverFlottant: View {

    let info: PresentedEventInfo
    let plotRect: CGRect

    @State private var popoverSize: CGSize = .zero

    var body: some View {
        PopoverEventDetail(event: info.event)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: PopoverSizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(PopoverSizeKey.self) { popoverSize = $0 }
            .position(x: clampedX, y: clampedY)
            // Cache la première frame (avant mesure GeometryReader) où
            // `clampedX` serait calculé avec une largeur nulle → évite
            // de voir le popover « sauter » de pillX à clampedX.
            .opacity(popoverSize == .zero ? 0 : 1)
    }

    /// Garde le centre X à l'intérieur de [plotRect.minX + halfW,
    /// plotRect.maxX - halfW] → le popover ne déborde jamais.
    private var clampedX: CGFloat {
        let halfW = popoverSize.width / 2
        let minX = plotRect.minX + halfW + 4
        let maxX = plotRect.maxX - halfW - 4
        return max(minX, min(maxX, info.pillX))
    }

    /// Sous la pill (pill center Y + ~28pt pour laisser la pill visible).
    /// Si le popover déborderait par le bas, on bascule au-dessus.
    private var clampedY: CGFloat {
        let dessous = info.pillY + 28 + popoverSize.height / 2
        if dessous + popoverSize.height / 2 <= plotRect.maxY - 4 {
            return dessous
        }
        // Bascule au-dessus de la pill
        let dessus = info.pillY - 18 - popoverSize.height / 2
        return max(plotRect.minY + popoverSize.height / 2 + 4, dessus)
    }
}

private struct PopoverSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Représente un event positionné sur l'overlay du chart — soit un
/// event simple, soit un cluster de 3+ events.
private struct PositionedEvent: Identifiable {
    let id: UUID
    let rendering: Rendering
    let x: CGFloat   // X relative au plot area (0 = gauche, plotWidth = droite)
    let level: Int   // 0 = level par défaut, 1 = décalé pour overlap

    enum Rendering {
        case single(NightEvent)
        case multi([NightEvent])
    }
}

/// Pill tappable seule. Le popover est désormais rendu au niveau
/// parent (clamping bord + zIndex max).
private struct EventPillTappable: View {

    let item: PositionedEvent
    /// `nil` → pill statique, sans détection de tap (cas Vue Toutes
    /// pour la pill lente moyenne).
    let onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            pill.onTapGesture { onTap() }
        } else {
            pill
        }
    }

    @ViewBuilder
    private var pill: some View {
        switch item.rendering {
        case .single(let e):
            Text(e.type.pillLabel(detail: e.detail))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(e.type.pillForeground)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(e.type.pillForeground.opacity(0.35), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        case .multi(let events):
            Text(events.map { $0.type.pillLabel(detail: $0.detail) }.joined(separator: " · "))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
    }
}

/// Popover détaillée affichée au-dessus d'une pill au tap. Titre
/// typé + corps reconstruit à partir de `event.detail` avec format
/// long (« 1.5 unités » au lieu de « 1.5u »).
private struct PopoverEventDetail: View {

    let event: NightEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(corps)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private var titre: String {
        switch event.type {
        case .rapide:    return "Injection rapide"
        case .resucrage: return "Resucrage"
        case .lente:     return "Injection lente"
        case .hypo:      return "Hypoglycémie"
        case .repas:     return "Repas"
        }
    }

    private var corps: String {
        let cleaned = event.detail
        switch event.type {
        case .rapide, .lente:
            return cleaned.replacingOccurrences(of: "u à", with: " unités à")
        case .resucrage, .repas:
            return cleaned.replacingOccurrences(of: "g à", with: "g de glucides à")
        case .hypo:
            return cleaned
        }
    }
}

// MARK: - EventType colors / labels for pills

private extension EventType {
    /// Fond léger (opacité 0.12) sur la pill — même teinte que
    /// `pillForeground` mais très diluée pour ne pas peser.
    var pillBackground: Color {
        switch self {
        case .rapide:    return Color(red: 207/255, green:  78/255, blue:  29/255).opacity(0.12) // orange-rouge
        case .resucrage: return Color(red: 151/255, green: 196/255, blue:  89/255).opacity(0.12) // vert clair
        case .lente:     return Color(red:  24/255, green:  95/255, blue: 165/255).opacity(0.12) // bleu
        case .hypo:      return Color(red: 226/255, green:  75/255, blue:  74/255).opacity(0.12)
        case .repas:     return Color(red:  41/255, green: 121/255, blue:  70/255).opacity(0.12) // vert forêt
        }
    }

    /// Couleur texte / bordure — teinte foncée pour bon contraste sur
    /// le fond léger correspondant.
    /// - Rapide → orange-rouge (action intense, rapide)
    /// - Lente → bleu (calme, longue durée)
    /// - Repas → vert (apport, neutre/positif)
    /// - Resucrage → olive (correction sucrée)
    /// - Hypo → rouge (alerte)
    var pillForeground: Color {
        switch self {
        case .rapide:    return Color(red: 192/255, green:  64/255, blue:  24/255) // #C04018
        case .resucrage: return Color(red:  59/255, green: 109/255, blue:  17/255) // #3B6D11
        case .lente:     return Color(red:  24/255, green:  95/255, blue: 165/255) // #185FA5
        case .hypo:      return Color(red: 163/255, green:  45/255, blue:  45/255) // #A32D2D
        case .repas:     return Color(red:  29/255, green: 105/255, blue:  60/255) // #1D693C
        }
    }

    /// Label compact pour la pill — extrait de `detail` la partie avant
    /// le « à » (« 1.5u », « 15g », « 58 »). Pour l'hypo on retire aussi
    /// « mg/dL » qui prendrait trop de place.
    func pillLabel(detail: String) -> String {
        var label = detail
        if let aRange = label.range(of: " à ") {
            label = String(label[..<aRange.lowerBound])
        }
        if self == .hypo {
            label = label.replacingOccurrences(of: " mg/dL", with: "")
        }
        return label.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Légende — atomes partagés

/// Forme d'une puce de légende. Mêmes 3 cas pour la vue « Toutes » et
/// la vue « Par nuit » — extraits au scope fichier pour réutilisation.
private enum FormePuceLegende {
    case ligne(Color, CGFloat)              // ligne horizontale (séries continues)
    case cercle(Color)                       // event ponctuel
    case ligneVerticalePointillee(Color)     // lente (RuleMark vertical dashed)
}

@ViewBuilder
private func puceLegende(forme: FormePuceLegende, texte: String) -> some View {
    HStack(spacing: 4) {
        switch forme {
        case .ligne(let c, let ep):
            Capsule(style: .continuous)
                .fill(c)
                .frame(width: 14, height: ep)
        case .cercle(let c):
            Circle()
                .fill(c)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        case .ligneVerticalePointillee(let c):
            Path { path in
                path.move(to: CGPoint(x: 1, y: 0))
                path.addLine(to: CGPoint(x: 1, y: 12))
            }
            .stroke(c, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            .frame(width: 2, height: 12)
        }
        Text(texte)
    }
}

// MARK: - Légende (vue « Toutes »)

private struct LegendeGraphique: View {
    var body: some View {
        HStack(spacing: 14) {
            puceLegende(forme: .ligne(.basaleTendanceMoy, 2.5), texte: "Moyenne des nuits")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Wrapper preview

// Sous `#if DEBUG` : le wrapper utilise `.mockBaisse`, qui n'existe qu'en
// Debug. Laissé hors du bloc, il cassait le build Release.
#if DEBUG
/// Holder léger qui possède `mode` + `indexSelectionne` en `@State`
/// pour les previews standalone du chart — l'app réelle passe ces
/// deux états depuis `DetailAnalyseBasaleVue`.
private struct _PreviewWrapperBasalChart: View {
    let nights: [NightChartData]

    @State private var mode: ModeAffichageGraphiqueBasale
    @State private var index: Int = 0

    init(
        nights: [NightChartData],
        initialMode: ModeAffichageGraphiqueBasale = .toutes
    ) {
        self.nights = nights
        self._mode = State(initialValue: initialMode)
    }

    var body: some View {
        CourbesNocturnesChart(
            nights: nights,
            mode: $mode,
            indexSelectionne: $index,
            chargePour: { _ in .mockBaisse }
        )
    }
}

// MARK: - Aperçus

#Preview("Toutes - 8 nuits") {
    _PreviewWrapperBasalChart(nights: AnalyseBasaleDetail.mockTropHaute.nightChartData)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Toutes - Hypo sur la moyenne") {
    _PreviewWrapperBasalChart(nights: AnalyseBasaleDetail.mockAvecHypoMoyenne.nightChartData)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Toutes - Outliers (haute + basse)") {
    _PreviewWrapperBasalChart(nights: AnalyseBasaleDetail.mockAvecOutliers.nightChartData)
        .padding(16)
        .background(Color(.systemGroupedBackground))
}

#Preview("Par nuit - Hyper outlier") {
    _PreviewWrapperBasalChart(
        nights: AnalyseBasaleDetail.mockAvecOutliers.nightChartData,
        initialMode: .parNuit
    )
    .padding(16)
    .background(Color(.systemGroupedBackground))
}

#Preview("Par nuit - Vue globale") {
    _PreviewWrapperBasalChart(
        nights: [.mockNuitValide],
        initialMode: .parNuit
    )
    .padding(16)
    .background(Color(.systemGroupedBackground))
}

#Preview("Par nuit - Partielle (zone 2 chaotique)") {
    _PreviewWrapperBasalChart(
        nights: [.mockNuitPartielle],
        initialMode: .parNuit
    )
    .padding(16)
    .background(Color(.systemGroupedBackground))
}
#endif
