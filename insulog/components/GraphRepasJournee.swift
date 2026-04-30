//
//  GraphRepasJournee.swift
//  insulog
//
//  Created by Alexandre on 30/04/2026.
//

import SwiftUI
import Charts

/// Graphique 24h des repas, façon Apple Health.
///
/// Architecture en deux couches :
/// - Une couche "fixe" qui dessine la légende de l'axe Y (gauche + droite),
///   les lignes verticales de grille et l'axe X — toujours rendue par un
///   `Chart` "fantôme" sans barres, mais avec le même `chartYScale` que les
///   pages scrollables.
/// - Une couche scrollable horizontale paginée, dans laquelle chaque page
///   est un `Chart` qui ne rend que ses `BarMark` (axes masqués). Comme le
///   `chartYScale` est partagé avec la couche fixe, les hauteurs de barres
///   s'alignent visuellement avec les graduations Y fixes.
///
/// Effet final : pendant le swipe, seules les **barres** glissent ; la
/// légende Y reste figée en place, exactement comme Apple Health.
struct GraphRepasJournee: View {

    let sections: [(titre: String, repas: [Repas])]

    /// Date sélectionnée — liée au parent pour qu'il puisse filtrer
    /// son contenu (liste de repas) sur la même journée.
    @Binding var selectedDate: Date

    /// Locale figée en français pour les libellés de date.
    private let localeFr = Locale(identifier: "fr_FR")

    /// Plage de jours navigables : les 30 derniers jours, du plus ancien
    /// au plus récent (today en dernier).
    private let jours: [Date] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }
    }()

    /// ID (= Date) du jour actuellement centré dans la `ScrollView`.
    /// Mis à jour en temps réel par SwiftUI pendant le swipe.
    @State private var dateScroll: Date?

    /// Hauteur réservée à la zone chart (excl. en-tête).
    private let hauteurChart: CGFloat = 200

    /// Largeur de la bande blanche qui contient la légende Y droite.
    /// Doit accueillir un label "100 g" + sa marge intérieure.
    private let legendWidth: CGFloat = 56

    /// Marge entre le bord droit de l'écran et le label de la légende —
    /// évite que le texte ne soit complètement collé au bord.
    private let legendMarge: CGFloat = 12

    /// Jour effectivement affiché (fallback sur today si rien n'est encore positionné).
    private var dateAffichee: Date {
        dateScroll ?? jours.last ?? Date()
    }

    /// Borne supérieure fixe de l'axe Y : on prend le max des totaux de
    /// glucides sur toutes les sections (toutes journées confondues),
    /// arrondi au pallier supérieur de 50g, avec un minimum de 100g.
    /// Garde une échelle stable entre les jours pour comparer visuellement.
    private var maxY: Int {
        let max = sections.flatMap(\.repas)
            .filter { !$0.aliments.isEmpty }
            .map(\.totalGlucides)
            .max() ?? 0
        let palier = ((max / 50) + 1) * 50
        return Swift.max(palier, 100)
    }

    /// Tous les repas non vides du jour donné, aplatis depuis les sections.
    private func repasPour(jour: Date) -> [Repas] {
        let cal = Calendar.current
        return sections.flatMap(\.repas)
            .filter { !$0.aliments.isEmpty }
            .filter { cal.isDate($0.heure, inSameDayAs: jour) }
    }

    /// Fenêtre 24h fixe pour un jour donné.
    private func domainePour(jour: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        let debut = cal.startOfDay(for: jour)
        let fin = cal.date(byAdding: .day, value: 1, to: debut) ?? debut.addingTimeInterval(86400)
        return debut...fin
    }

    /// Libellé "intelligent" : Aujourd'hui / Hier / "Lun. 28 avr."
    private var libelleJour: String {
        let cal = Calendar.current
        if cal.isDateInToday(dateAffichee) { return "Aujourd'hui" }
        if cal.isDateInYesterday(dateAffichee) { return "Hier" }
        return dateAffichee.formatted(
            Date.FormatStyle()
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .locale(localeFr)
        ).capitalized
    }

    private var totalGlucidesAffiche: Int {
        repasPour(jour: dateAffichee).reduce(0) { $0 + $1.totalGlucides }
    }

    private var nombreRepasAffiche: Int {
        repasPour(jour: dateAffichee).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            pages
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .onAppear {
            if dateScroll == nil {
                dateScroll = jours.last
            }
        }
        .onChange(of: dateScroll) { _, nouvelle in
            // Reflète le jour visible vers le parent pour qu'il filtre
            // sa liste de repas en dessous.
            if let nouvelle { selectedDate = nouvelle }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: changerJour(de: -1)
            case .decrement: changerJour(de: 1)
            @unknown default: break
            }
        }
    }

    /// En-tête : date discrète puis chiffres clés en gros (style Apple Health).
    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(libelleJour)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: libelleJour)

            chiffresCles
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    /// Total glucides en très gros + nombre de repas à droite.
    @ViewBuilder
    private var chiffresCles: some View {
        if nombreRepasAffiche == 0 {
            Text("Aucune donnée")
                .font(.title.weight(.bold))
                .foregroundStyle(.tertiary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(totalGlucidesAffiche)")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("g")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(nombreRepasAffiche) repas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .animation(.easeOut(duration: 0.2), value: dateAffichee)
        }
    }

    /// Pages scrollables + bande légende fixe par-dessus à droite.
    /// Les barres défilent **sous** la bande blanche, ce qui donne
    /// l'illusion que les données s'effacent en arrivant à droite.
    private var pages: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(jours, id: \.self) { jour in
                        barresPour(jour: jour)
                            .containerRelativeFrame(.horizontal)
                            .id(jour)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $dateScroll)
            .scrollIndicators(.hidden)

            legendeFixe
        }
        .frame(height: hauteurChart)
        .padding(.bottom, 16)
    }

    /// Bande de légende Y fixe sur le bord droit. Dessinée par un `Chart`
    /// "fantôme" sans données (seulement les `AxisMarks(.trailing)`), avec
    /// un fond `Color(.systemBackground)` qui masque les barres qui passent
    /// dessous pendant le scroll. Le `chartPlotStyle.padding(.bottom: 24)`
    /// réserve la même hauteur d'axe X que les charts scrollables, pour
    /// que les graduations Y s'alignent verticalement avec les barres.
    private var legendeFixe: some View {
        Chart {
            BarMark(
                x: .value("h", Calendar.current.startOfDay(for: Date())),
                y: .value("g", maxY)
            )
            .opacity(0)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...maxY)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let g = value.as(Int.self) {
                        Text("\(g) g").font(.caption2)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.padding(.bottom, 24)
        }
        .frame(width: legendWidth)
        .padding(.trailing, legendMarge)
        .background(Color(.systemBackground))
        .allowsHitTesting(false)
    }

    /// Page individuelle : un `Chart` qui rend ses `BarMark` et son axe X.
    /// Y axis masqué — c'est `legendeFixe` qui s'en charge.
    ///
    /// `chartPlotStyle.padding(.trailing, legendWidth + legendMarge)` réserve
    /// l'espace exact de la bande légende droite pour que **toutes** les
    /// barres restent visibles, même celles tard dans la journée (dîner).
    @ViewBuilder
    private func barresPour(jour: Date) -> some View {
        let repas = repasPour(jour: jour)
        let domain = domainePour(jour: jour)

        Chart(repas) { unRepas in
            BarMark(
                x: .value("Heure", unRepas.heure),
                y: .value("Glucides", unRepas.totalGlucides),
                width: .fixed(8)
            )
            .foregroundStyle(Color.blue.gradient)
            .cornerRadius(3)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...maxY)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().locale(localeFr))
            }
        }
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.trailing, legendWidth + legendMarge)
        }
        .padding(.leading, 16)
        .overlay {
            if repas.isEmpty {
                Text("Aucun repas enregistré")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Accessibilité

    /// Recule ou avance d'un jour via VoiceOver.
    private func changerJour(de delta: Int) {
        guard let courant = dateScroll,
              let idx = jours.firstIndex(of: courant) else { return }
        let nouvelIndex = idx + delta
        guard nouvelIndex >= 0 && nouvelIndex < jours.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            dateScroll = jours[nouvelIndex]
        }
    }
}

// MARK: - Preview helpers

private func _previewDate(_ h: Int, _ m: Int = 0, daysAgo: Int = 0) -> Date {
    let cal = Calendar.current
    let day = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? Date()
}

private let _previewSections: [(titre: String, repas: [Repas])] = [
    (titre: "Petit déjeuner", repas: [
        Repas(heure: _previewDate(7, 30), aliments: [
            Aliment(emoji: "🥣", nom: "Flocons", quantite: 80, glucides: 54, insuline: 3),
        ]),
        Repas(heure: _previewDate(8, 0, daysAgo: 1), aliments: [
            Aliment(emoji: "🥐", nom: "Croissant", quantite: 60, glucides: 30, insuline: 2),
        ]),
    ]),
    (titre: "Déjeuner", repas: [
        Repas(heure: _previewDate(12, 30), aliments: [
            Aliment(emoji: "🍝", nom: "Pâtes", quantite: 90, glucides: 68, insuline: 3.5),
        ]),
    ]),
    (titre: "Dîner", repas: [
        Repas(heure: _previewDate(20, 30, daysAgo: 1), aliments: [
            Aliment(emoji: "🍕", nom: "Pizza", quantite: 300, glucides: 90, insuline: 5),
        ]),
    ]),
]

#Preview("Avec repas") {
    @Previewable @State var date = Calendar.current.startOfDay(for: Date())
    ScrollView {
        VStack(spacing: 0) {
            GraphRepasJournee(sections: _previewSections, selectedDate: $date)
            Color(.systemGroupedBackground).frame(height: 600)
        }
    }
}

#Preview("État vide") {
    @Previewable @State var date = Calendar.current.startOfDay(for: Date())
    ScrollView {
        VStack(spacing: 0) {
            GraphRepasJournee(sections: [], selectedDate: $date)
            Color(.systemGroupedBackground).frame(height: 600)
        }
    }
}
